# app/services/tenants/users/create_service.rb
# Servicio para crear usuarios en un tenant con rol y scopes
# ACTUALIZADO: Con ScopeCompatibilityValidator integrado

module Tenants
  module Users
    class CreateService
      include ServiceResultHelper

      attr_reader :params, :tenant, :current_user

      def initialize(params:, tenant:, current_user:)
        @params = params
        @tenant = tenant
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # 1. Validar parámetros básicos
        validation_result = validate_params
        return validation_result if validation_result.failure?

        # 2. 🆕 NUEVO: Validar compatibilidad rol-scope (CRÍTICO)
        compatibility_result = validate_scope_compatibility
        return compatibility_result if compatibility_result.failure?

        # 3. 🆕 NUEVO: Validar que los recursos existan en el tenant
        resources_result = validate_resources_exist
        return resources_result if resources_result.failure?

        # 4. Validar límite de usuarios
        if tenant.user_limit_reached?
          return failure(errors: "User limit reached for this tenant")
        end

        ActiveRecord::Base.transaction do
          # 5. Crear o encontrar usuario
          user_result = find_or_create_user
          return user_result if user_result.failure?
          user = user_result.data

          # 6. Verificar que no tenga membresía activa con este rol
          if user.tenant_memberships.exists?(
            tenant_id: tenant.id,
            role_id: @role.id,
            status: "active"
          )
            return failure(errors: "User already has this role in this tenant")
          end

          # 7. 🔄 CRÍTICO: Asignar scopes ANTES de crear membership
          if @role.requires_any_scope? || params[:node_scopes].present? || params[:vehicle_scopes].present?
            scopes_result = assign_scopes(user)
            return scopes_result if scopes_result.failure?
          end

          # 8. Crear membresía (DESPUÉS de scopes)
          membership_result = create_membership(user)
          return membership_result if membership_result.failure?
          membership = membership_result.data

          # 9. Configurar PaperTrail
          set_paper_trail_context(user, membership)

          # 10. TODO: Enviar email de bienvenida/invitación
          # enqueue_welcome_email(user) unless params[:skip_email]

          success(
            data: {
              user: user,
              membership: membership,
              node_scopes: user.user_node_scopes.where(tenant_id: tenant.id),
              vehicle_scopes: user.user_vehicle_scopes.where(tenant_id: tenant.id),
              warnings: @scope_warnings # 🆕 Incluir warnings de validación
            },
            message: params[:password].present? ?
              "User created successfully" :
              "User invited successfully"
          )
        end
      rescue StandardError => e
        Rails.logger.error("[CreateUserService] Error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        failure(errors: "Failed to create user: #{e.message}")
      end

      private

      # ============================================
      # VALIDACIONES
      # ============================================

      def validate_params
        required = %i[email first_name last_name role_slug]
        missing = required.select { |f| params[f].blank? }

        if missing.any?
          return failure(errors: "Missing required fields: #{missing.join(', ')}")
        end

        unless params[:email] =~ URI::MailTo::EMAIL_REGEXP
          return failure(errors: "Invalid email format")
        end

        # Validar que el rol exista y guardarlo para uso posterior
        @role = Role.tenant_roles.find_by(slug: params[:role_slug])
        unless @role
          return failure(errors: "Invalid role: #{params[:role_slug]}")
        end

        success(data: { valid: true })
      end

      # 🆕 NUEVO: Validar compatibilidad entre rol y scopes usando el validador
      def validate_scope_compatibility
        validator = ScopeCompatibilityValidator.new(
          role: @role,
          node_scopes: params[:node_scopes],
          vehicle_scopes: params[:vehicle_scopes]
        )

        result = validator.validate

        # Guardar warnings para incluirlos en la respuesta final
        @scope_warnings = result[:warnings]

        unless result[:valid]
          Rails.logger.warn("[CreateUserService] Scope compatibility validation failed")
          Rails.logger.warn("[CreateUserService] Role: #{@role.slug}")
          Rails.logger.warn("[CreateUserService] Errors: #{result[:errors].join(', ')}")

          return failure(
            errors: result[:errors],
            meta: {
              validation_summary: result[:summary],
              detailed_explanation: validator.detailed_explanation
            }
          )
        end

        # Log de warnings si existen
        if result[:warnings].any?
          Rails.logger.info("[CreateUserService] Scope compatibility warnings:")
          result[:warnings].each { |w| Rails.logger.info("[CreateUserService]   - #{w}") }
        end

        success(data: { compatible: true, warnings: result[:warnings] })
      end

      # 🆕 NUEVO: Validar que los nodos y vehículos existan en el tenant
      def validate_resources_exist
        errors = []

        # Validar nodos organizacionales
        if params[:node_scopes].present?
          node_validation = validate_organizational_nodes
          errors.concat(node_validation) if node_validation.any?
        end

        # Validar vehículos
        if params[:vehicle_scopes].present?
          vehicle_validation = validate_vehicles
          errors.concat(vehicle_validation) if vehicle_validation.any?
        end

        return failure(errors: errors) if errors.any?

        success(data: { resources_valid: true })
      end

      def validate_organizational_nodes
        errors = []
        node_ids = params[:node_scopes].map { |ns| ns[:organizational_node_id] }.compact.uniq

        # Verificar que existan en el tenant
        existing_nodes = OrganizationalNode.where(
          id: node_ids,
          tenant_id: tenant.id,
          status: "active"
        ).pluck(:id)

        missing_nodes = node_ids - existing_nodes
        if missing_nodes.any?
          errors << "Organizational nodes not found in this tenant: #{missing_nodes.join(', ')}"
        end

        # Verificar que los nodos permitan asignación de usuarios
        if existing_nodes.any?
          invalid_nodes = OrganizationalNode.where(id: existing_nodes)
            .joins(:level)
            .where(organizational_node_levels: { allows_users: false })
            .pluck(:id, :name)

          if invalid_nodes.any?
            node_names = invalid_nodes.map { |id, name| "#{name} (ID: #{id})" }.join(", ")
            errors << "These organizational nodes do not allow user assignment: #{node_names}"
          end
        end

        errors
      end

      def validate_vehicles
        errors = []
        vehicle_ids = params[:vehicle_scopes].map { |vs| vs[:vehicle_id] }.compact.uniq

        # Verificar que existan en el tenant
        existing_vehicles = Vehicle.where(
          id: vehicle_ids,
          tenant_id: tenant.id
        ).pluck(:id)

        missing_vehicles = vehicle_ids - existing_vehicles
        if missing_vehicles.any?
          errors << "Vehicles not found in this tenant: #{missing_vehicles.join(', ')}"
        end

        # Verificar que los vehículos estén en nodos que permitan vehículos
        if existing_vehicles.any?
          invalid_vehicles = Vehicle.where(id: existing_vehicles)
            .joins(organizational_node: :level)
            .where(organizational_node_levels: { allows_vehicles: false })
            .pluck(:id, :plate_number)

          if invalid_vehicles.any?
            vehicle_plates = invalid_vehicles.map { |id, plate| "#{plate} (ID: #{id})" }.join(", ")
            errors << "These vehicles are in nodes that don't allow vehicle assignment: #{vehicle_plates}"
          end
        end

        # Validar fechas de validez si se proporcionan
        params[:vehicle_scopes].each do |vs|
          if vs[:valid_from].present? && vs[:valid_until].present?
            valid_from = parse_datetime(vs[:valid_from])
            valid_until = parse_datetime(vs[:valid_until])

            if valid_from && valid_until && valid_from >= valid_until
              errors << "Vehicle #{vs[:vehicle_id]}: valid_from must be before valid_until"
            end
          end
        end

        errors
      end

      def parse_datetime(value)
        return value if value.is_a?(DateTime) || value.is_a?(Time)
        DateTime.parse(value.to_s) rescue nil
      end

      # ============================================
      # CREACIÓN DE USUARIO
      # ============================================

      def find_or_create_user
        email = params[:email].downcase.strip
        existing_user = User.find_by_email(email)

        if existing_user
          if existing_user.deleted?
            return failure(errors: "User account is deactivated")
          end
          return success(data: existing_user)
        end

        # Crear nuevo usuario
        user_params = {
          email: email,
          first_name: params[:first_name],
          last_name: params[:last_name],
          phone: params[:phone],
          invited_by: current_user
        }

        # Si tiene password, crear activado
        if params[:password].present?
          user_params[:password] = params[:password]
          user_params[:password_confirmation] = params[:password]
          user_params[:email_verified_at] = Time.current
        else
          # Sin password = invitación
          user_params[:password] = generate_temporary_password
          user_params[:password_confirmation] = user_params[:password]
        end

        user = User.create!(user_params)
        success(data: user)
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      # ============================================
      # ASIGNACIÓN DE SCOPES
      # ============================================

      def assign_scopes(user)
        # Asignar node scopes
        if params[:node_scopes].present?
          node_result = assign_node_scopes(user)
          return node_result if node_result.failure?
        end

        # Asignar vehicle scopes
        if params[:vehicle_scopes].present?
          vehicle_result = assign_vehicle_scopes(user)
          return vehicle_result if vehicle_result.failure?
        end

        success(data: { assigned: true })
      end

      def assign_node_scopes(user)
        params[:node_scopes].each do |node_scope_params|
          node = OrganizationalNode.find(node_scope_params[:organizational_node_id])

          UserNodeScope.create!(
            user: user,
            organizational_node: node,
            tenant: tenant,
            access_type: node_scope_params[:access_type] || "read",
            include_children: node_scope_params.fetch(:include_children, true),
            created_by: current_user.id
          )
        end

        success(data: { node_scopes_created: params[:node_scopes].size })
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Organizational node not found: #{e.message}")
      end

      def assign_vehicle_scopes(user)
        params[:vehicle_scopes].each do |vehicle_scope_params|
          vehicle = Vehicle.find(vehicle_scope_params[:vehicle_id])

          UserVehicleScope.create!(
            user: user,
            vehicle: vehicle,
            tenant: tenant,
            access_type: vehicle_scope_params[:access_type] || "read",
            valid_from: vehicle_scope_params[:valid_from],
            valid_until: vehicle_scope_params[:valid_until],
            created_by: current_user.id
          )
        end

        success(data: { vehicle_scopes_created: params[:vehicle_scopes].size })
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Vehicle not found: #{e.message}")
      end

      # ============================================
      # CREACIÓN DE MEMBERSHIP
      # ============================================

      def create_membership(user)
        membership_params = {
          user: user,
          tenant: tenant,
          role_id: @role.id,
          status: params[:password].present? ? "active" : "invited",
          is_primary_admin: false,
          is_default: user.tenant_memberships.empty?,
          created_by: current_user.id
        }

        membership = TenantMembership.create!(membership_params)
        success(data: membership)
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      # ============================================
      # HELPERS
      # ============================================

      def generate_temporary_password
        SecureRandom.urlsafe_base64(16)
      end

      def set_paper_trail_context(user, membership)
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "create_user",
            role_assigned: @role.name,
            role_slug: @role.slug,
            scopes_assigned: {
              nodes: params[:node_scopes]&.size || 0,
              vehicles: params[:vehicle_scopes]&.size || 0
            },
            scope_warnings: @scope_warnings&.any? ? @scope_warnings : nil,
            user_status: membership.status
          }
        }
      end
    end
  end
end
