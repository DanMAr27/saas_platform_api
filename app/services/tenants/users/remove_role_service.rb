# app/services/tenants/users/remove_role_service.rb

module Tenants
  module Users
    class RemoveRoleService
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
          return failure(errors: "Cannot remove primary admin role")
        end

        # Verificar que el usuario tenga al menos otro rol activo en el tenant
        user = membership.user
        tenant = membership.tenant

        other_active_memberships = user.tenant_memberships
                                      .where(tenant_id: tenant.id)
                                      .where.not(id: membership.id)
                                      .active
                                      .kept
                                      .count

        if other_active_memberships.zero?
          return failure(
            errors: "Cannot remove last role. User must have at least one active role or be completely removed from tenant"
          )
        end

        ActiveRecord::Base.transaction do
          role_name = membership.role.name

          # Soft delete de la membresía específica
          membership.discard

          # Si este rol tenía scopes específicos (opcional: eliminarlos)
          # En tu caso actual los scopes son por usuario-tenant, no por rol
          # Pero podrías implementar lógica adicional aquí si es necesario

          # Configurar PaperTrail
          set_paper_trail_context(role_name)

          success(
            data: { removed: true },
            message: "Role '#{role_name}' removed successfully"
          )
        end
      rescue StandardError => e
        Rails.logger.error("[RemoveRoleService] Error: #{e.message}")
        failure(errors: "Failed to remove role")
      end

      private

      def set_paper_trail_context(role_name)
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: membership.tenant_id,
            performed_action: "remove_user_role",
            role_removed: role_name
          }
        }
      end
    end
  end
end
