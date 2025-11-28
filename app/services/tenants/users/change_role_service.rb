# app/services/tenant/users/change_role_service.rb

module Tenant
  module Users
    class ChangeRoleService
      include ServiceResultHelper

      attr_reader :membership, :new_role_slug, :current_user

      def initialize(membership:, new_role_slug:, current_user:)
        @membership = membership
        @new_role_slug = new_role_slug
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que no sea el primary admin
        if membership.is_primary_admin?
          return failure(errors: "Cannot change role of primary admin")
        end

        # Buscar nuevo rol
        new_role = Role.tenant_roles.find_by(slug: new_role_slug)
        unless new_role
          return failure(errors: "Invalid role")
        end

        # Si es el mismo rol, no hacer nada
        if membership.role_id == new_role.id
          return success(
            data: { membership: membership },
            message: "Role is already assigned"
          )
        end

        ActiveRecord::Base.transaction do
          old_role = membership.role

          # Actualizar rol
          membership.update!(role_id: new_role.id)

          # Ajustar scopes según requerimientos del nuevo rol
          adjust_scopes_for_role(new_role, old_role)

          # Configurar PaperTrail
          set_paper_trail_context(old_role, new_role)

          success(
            data: { membership: membership.reload },
            message: "Role changed successfully from #{old_role.name} to #{new_role.name}"
          )
        end
      rescue StandardError => e
        Rails.logger.error("[ChangeRoleService] Error: #{e.message}")
        failure(errors: "Failed to change role")
      end

      private

      def adjust_scopes_for_role(new_role, old_role)
        user = membership.user
        tenant = membership.tenant

        # Si el nuevo rol NO requiere scopes y el anterior SÍ,
        # eliminar scopes (opcional, según lógica de negocio)
        if !new_role.requires_scope? && old_role.requires_scope?
          # Opción 1: Mantener scopes existentes
          # Opción 2: Eliminar scopes
          # user.user_node_scopes.where(tenant_id: tenant.id).destroy_all
          # user.user_vehicle_scopes.where(tenant_id: tenant.id).destroy_all
        end

        # Si el nuevo rol requiere scopes y no tiene ninguno, advertir
        if new_role.requires_scope?
          has_scopes = user.user_node_scopes.exists?(tenant_id: tenant.id) ||
                      user.user_vehicle_scopes.exists?(tenant_id: tenant.id)

          unless has_scopes
            Rails.logger.warn(
              "[ChangeRoleService] User #{user.id} assigned role '#{new_role.name}' " \
              "which requires scopes, but user has no scopes assigned"
            )
          end
        end
      end

      def set_paper_trail_context(old_role, new_role)
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: membership.tenant_id,
            performed_action: "change_user_role",
            old_role: old_role.name,
            new_role: new_role.name
          }
        }
      end
    end
  end
end
