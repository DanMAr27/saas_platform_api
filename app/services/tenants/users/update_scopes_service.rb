# app/services/tenant/users/update_scopes_service.rb

module Tenant
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
        ActiveRecord::Base.transaction do
          # Actualizar node scopes
          if params[:node_scopes].present?
            update_node_scopes_result = update_node_scopes
            return update_node_scopes_result if update_node_scopes_result.failure?
          end

          # Actualizar vehicle scopes
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
        failure(errors: "Failed to update scopes")
      end

      private

      def update_node_scopes
        # Eliminar scopes actuales
        user.user_node_scopes.where(tenant_id: tenant.id).destroy_all

        # Crear nuevos scopes
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

        success(data: { updated: true })
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Node not found: #{e.message}")
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      def update_vehicle_scopes
        # Eliminar scopes actuales
        user.user_vehicle_scopes.where(tenant_id: tenant.id).destroy_all

        # Crear nuevos scopes
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

        success(data: { updated: true })
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Vehicle not found: #{e.message}")
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "update_user_scopes"
          }
        }
      end
    end
  end
end
