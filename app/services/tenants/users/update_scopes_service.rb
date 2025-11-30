# app/services/tenants/users/update_scopes_service.rb

module Tenants
  module Users
    class UpdateScopesService
      include ServiceResultHelper

      attr_reader :user, :tenant, :params, :current_user

      def initialize(user:, tenant:, params:, current_user:)
        @user = user
        @tenant = tenant
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que el usuario requiere scopes según sus roles
        validation_result = validate_scope_requirements
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          # Actualizar node scopes si se proporcionaron
          if params[:node_scopes].present?
            update_node_scopes_result = update_node_scopes
            return update_node_scopes_result if update_node_scopes_result.failure?
          end

          # Actualizar vehicle scopes si se proporcionaron
          if params[:vehicle_scopes].present?
            update_vehicle_scopes_result = update_vehicle_scopes
            return update_vehicle_scopes_result if update_vehicle_scopes_result.failure?
          end

          # Configurar PaperTrail
          set_paper_trail_context

          success(
            data: {
              user: user,
              node_scopes: user.user_node_scopes.where(tenant_id: tenant.id),
              vehicle_scopes: user.user_vehicle_scopes.where(tenant_id: tenant.id)
            },
            message: "Scopes updated successfully"
          )
        end
      rescue StandardError => e
        Rails.logger.error("[UpdateScopesService] Error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        failure(errors: "Failed to update scopes: #{e.message}")
      end

      private

      def validate_scope_requirements
        # Obtener todos los roles activos del usuario en el tenant
        user_roles = user.tenant_memberships
                        .where(tenant_id: tenant.id)
                        .active
                        .kept
                        .includes(:role)
                        .map(&:role)

        # Verificar si algún rol requiere scopes
        requires_scopes = user_roles.any?(&:requires_scope?)

        if requires_scopes
          # Si requiere scopes, validar que se proporcione al menos uno
          if params[:node_scopes].blank? && params[:vehicle_scopes].blank?
            role_names = user_roles.select(&:requires_scope?).map(&:name).join(", ")
            return failure(
              errors: "User has roles (#{role_names}) that require at least one scope assignment"
            )
          end
        end

        success(data: { valid: true })
      end

      def update_node_scopes
        # Eliminar scopes actuales
        user.user_node_scopes.where(tenant_id: tenant.id).destroy_all

        # Crear nuevos scopes
        params[:node_scopes].each do |node_scope_params|
          node = OrganizationalNode.find(node_scope_params[:organizational_node_id])

          unless node.tenant_id == tenant.id
            return failure(errors: "Node #{node.id} does not belong to this tenant")
          end

          UserNodeScope.create!(
            user: user,
            organizational_node: node,
            tenant: tenant,
            access_type: node_scope_params[:access_type] || "read",
            include_children: node_scope_params.fetch(:include_children, true),
            created_by: current_user.id
          )
        end

        success(data: { updated: true })
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Node not found: #{e.message}")
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages.join(", "))
      end

      def update_vehicle_scopes
        # Eliminar scopes actuales
        user.user_vehicle_scopes.where(tenant_id: tenant.id).destroy_all

        # Crear nuevos scopes
        params[:vehicle_scopes].each do |vehicle_scope_params|
          vehicle = Vehicle.find(vehicle_scope_params[:vehicle_id])

          unless vehicle.tenant_id == tenant.id
            return failure(errors: "Vehicle #{vehicle.id} does not belong to this tenant")
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

        success(data: { updated: true })
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Vehicle not found: #{e.message}")
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages.join(", "))
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "update_user_scopes",
            node_scopes_count: params[:node_scopes]&.size || 0,
            vehicle_scopes_count: params[:vehicle_scopes]&.size || 0
          }
        }
      end
    end
  end
end
