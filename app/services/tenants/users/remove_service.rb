# app/services/tenant/users/remove_service.rb

module Tenant
  module Users
    class RemoveService
      include ServiceResultHelper

      attr_reader :membership, :current_user

      def initialize(membership:, current_user:)
        @membership = membership
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que no sea el primary admin
        if membership.is_primary_admin?
          return failure(errors: "Cannot remove primary admin from tenant")
        end

        ActiveRecord::Base.transaction do
          user = membership.user
          tenant = membership.tenant

          # Eliminar scopes asociados
          user.user_node_scopes.where(tenant_id: tenant.id).destroy_all
          user.user_vehicle_scopes.where(tenant_id: tenant.id).destroy_all

          # Soft delete de la membresía
          membership.discard

          # Configurar PaperTrail
          set_paper_trail_context

          success(
            data: { removed: true },
            message: "User removed from tenant successfully"
          )
        end
      rescue StandardError => e
        Rails.logger.error("[RemoveUserService] Error: #{e.message}")
        failure(errors: "Failed to remove user")
      end

      private

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: membership.tenant_id,
            performed_action: "remove_user_from_tenant"
          }
        }
      end
    end
  end
end
