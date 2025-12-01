# app/services/tenants/users/create_service.rb
# Servicio para crear usuarios en un tenant con rol y scopes
# ACTUALIZADO: Con validación de compatibilidad rol-scope usando Scopeable

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

        # 2. 🆕 NUEVO: Validar compatibilidad rol-scope
        compatibility_result = validate_role_scope_compatibility
        return compatibility_result if compatibility_result.failure?

        # 3. Validar límite de usuarios
        if tenant.user_limit_reached?
          return failure(errors: "User limit reached for this tenant")
        end

        ActiveRecord::Base.transaction do
          # 4. Crear o encontrar usuario
          user_result = find_or_create_user
          return user_result if user_result.failure?
          user = user_result.data

          # 5. Verificar que no tenga membresía activa con este rol
          if user.tenant_memberships.exists?(
            tenant_id: tenant.id,
            role_id: @role.id,  # Usar el rol ya cargado
            status: "active"
          )
            return failure(errors: "User already has this role in this tenant")
          end

          # 6. 🔄 CAMBIO CRÍTICO: Asignar scopes ANTES de crear membership
          if @role.requires_any_scope?
            scopes_result = assign_scopes(user)
            return scopes_result if scopes_result.failure?
          end

          # 7. Crear membresía (ahora los scopes ya existen)
          membership_result = create_membership(user)
          return membership_result if membership_result.failure?
          membership = membership_result.data

          # 8. Configurar PaperTrail
          set_paper_trail_context

          # 9. TODO: Enviar email de bienvenida/invitación

          success(
            data: {
              user: user,
              membership: membership,
              node_scopes: user.user_node_scopes.where(tenant_id: tenant.id),
              vehicle_scopes: user.user_vehicle_scopes.where(tenant_id: tenant.id)
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

      # 🆕 NUEVO: Validar compatibilidad entre rol y scopes proporcionados
      def validate_role_scope_compatibility
        # Usar el método del concern Scopeable
        validation = @role.validate_scope_compatibility(
          node_scopes: params[:node_scopes],
          vehicle_scopes: params[:vehicle_scopes]
        )

        unless validation[:valid]
          return failure(errors: validation[:errors])
        end

        # Validación adicional: Si proporciona node scopes, verificar que existan
        if params[:node_scopes].present?
          node_ids = params[:node_scopes].map { |ns| ns[:organizational_node_id] }.compact
          existing_nodes = OrganizationalNode.where(
            id: node_ids,
            tenant_id: tenant.id
          ).pluck(:id)

          missing_nodes = node_ids - existing_nodes
          if missing_nodes.any?
            return failure(errors: "Nodes not found in this tenant: #{missing_nodes.join(', ')}")
          end

          # Validar que los nodos permitan asignación de usuarios
          invalid_nodes = OrganizationalNode.where(id: node_ids)
            .joins(:level)
            .where(organizational_node_levels: { allows_users: false })
            .pluck(:id)

          if invalid_nodes.any?
            return failure(
              errors: "These nodes do not allow user assignment: #{invalid_nodes.join(', ')}"
            )
          end
        end

        # Validación adicional: Si proporciona vehicle scopes, verificar que existan
        if params[:vehicle_scopes].present?
          vehicle_ids = params[:vehicle_scopes].map { |vs| vs[:vehicle_id] }.compact
          existing_vehicles = Vehicle.where(
            id: vehicle_ids,
            tenant_id: tenant.id
          ).pluck(:id)

          missing_vehicles = vehicle_ids - existing_vehicles
          if missing_vehicles.any?
            return failure(
              errors: "Vehicles not found in this tenant: #{missing_vehicles.join(', ')}"
            )
          end

          # Validar que los vehículos estén en nodos que permitan vehículos
          invalid_vehicles = Vehicle.where(id: vehicle_ids)
            .joins(organizational_node: :level)
            .where(organizational_node_levels: { allows_vehicles: false })
            .pluck(:id)

          if invalid_vehicles.any?
            return failure(
              errors: "These vehicles are in nodes that don't allow vehicles: #{invalid_vehicles.join(', ')}"
            )
          end
        end

        success(data: { compatible: true })
      end

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

      # 🔄 MOVIDO ANTES de create_membership
      def assign_scopes(user)
        # Asignar node scopes
        if params[:node_scopes].present?
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
        end

        # Asignar vehicle scopes
        if params[:vehicle_scopes].present?
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
        end

        success(data: { assigned: true })
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Resource not found: #{e.message}")
      end

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

      def generate_temporary_password
        SecureRandom.urlsafe_base64(16)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "create_user",
            role_assigned: @role.name,
            scopes_assigned: {
              nodes: params[:node_scopes]&.size || 0,
              vehicles: params[:vehicle_scopes]&.size || 0
            }
          }
        }
      end
    end
  end
end
