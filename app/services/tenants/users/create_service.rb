# app/services/tenant/users/create_service.rb

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
        # Validar parámetros
        validation_result = validate_params
        return validation_result if validation_result.failure?

        # Validar límite de usuarios
        if tenant.user_limit_reached?
          return failure(errors: "User limit reached for this tenant")
        end

        ActiveRecord::Base.transaction do
          # Crear o encontrar usuario
          user_result = find_or_create_user
          return user_result if user_result.failure?
          user = user_result.data

          # Verificar que no tenga membresía activa
          if user.tenant_memberships.exists?(tenant_id: tenant.id, status: "active")
            return failure(errors: "User already belongs to this tenant")
          end

          # Crear membresía con rol
          membership_result = create_membership(user)
          return membership_result if membership_result.failure?
          membership = membership_result.data

          # Asignar scopes según rol
          scopes_result = assign_scopes(user)
          return scopes_result if scopes_result.failure?

          # Configurar PaperTrail
          set_paper_trail_context

          # TODO: Enviar email de bienvenida/invitación

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
        failure(errors: "Failed to create user")
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

        # Validar que el rol exista
        unless Role.tenant_roles.exists?(slug: params[:role_slug])
          return failure(errors: "Invalid role")
        end

        # Validar scopes si el rol los requiere
        role = Role.find_by(slug: params[:role_slug])
        if role.requires_scope?
          if params[:node_scopes].blank? && params[:vehicle_scopes].blank?
            return failure(
              errors: "Role '#{role.name}' requires at least one scope assignment"
            )
          end
        end

        success(data: { valid: true })
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

      def create_membership(user)
        role = Role.find_by!(slug: params[:role_slug])

        membership_params = {
          user: user,
          tenant: tenant,
          role_id: role.id,
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

      def assign_scopes(user)
        # Asignar node scopes
        if params[:node_scopes].present?
          params[:node_scopes].each do |node_scope_params|
            node = OrganizationalNode.find(node_scope_params[:organizational_node_id])

            unless node.tenant_id == tenant.id
              return failure(errors: "Node does not belong to this tenant")
            end

            UserNodeScope.create!(
              user: user,
              organizational_node: node,
              tenant: tenant,
              access_type: node_scope_params[:access_type] || "read",
              include_children: node_scope_params[:include_children] != false,
              created_by: current_user.id
            )
          end
        end

        # Asignar vehicle scopes
        if params[:vehicle_scopes].present?
          params[:vehicle_scopes].each do |vehicle_scope_params|
            vehicle = Vehicle.find(vehicle_scope_params[:vehicle_id])

            unless vehicle.tenant_id == tenant.id
              return failure(errors: "Vehicle does not belong to this tenant")
            end

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

      def generate_temporary_password
        SecureRandom.urlsafe_base64(16)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "create_user"
          }
        }
      end
    end
  end
end
