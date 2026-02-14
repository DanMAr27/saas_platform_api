module Management
  class UserPolicy < ApplicationPolicy
    def index?
      tenant_admin_or_manager?
    end

    def show?
      return false unless record_in_same_tenant?
      tenant_admin_or_manager? || owner?
    end

    def create?
      tenant_admin?
    end

    def update?
      return false unless record_in_same_tenant?

      # Admin puede editar a cualquiera excepto a otros Admins (a menos que sea él mismo)
      if tenant_admin?
        return true if owner? # Editarse a sí mismo
        return !target_is_admin? # Editar a otros no-admins
      end

      # Manager no puede editar usuarios
      false
    end

    def destroy?
      return false unless record_in_same_tenant?

      # Solo Admin puede borrar
      # No puede borrar al Primary Admin
      # No puede borrarse a sí mismo
      tenant_admin? && !target_is_primary_admin? && !owner?
    end

    # Gestión de invitaciones
    def invite?
      create?
    end

    def resend_invitation?
      index?
    end

    # Acciones específicas
    def change_role?
      update?
    end

    def remove_from_tenant?
      destroy?
    end

    # Permission helpers for scopes
    def manage_scopes?
      tenant_admin_or_manager?
    end

    private

    def current_tenant_id
      ActsAsTenant.current_tenant&.id
    end

    def record_in_same_tenant?
      return false unless current_tenant_id
      # Verificar si el usuario objetivo tiene membresía en el tenant actual
      record.tenant_memberships
            .where(tenant_id: current_tenant_id)
            .exists?
    end

    def tenant_admin?
      return false unless current_tenant_id
      user.tenant_admin?(current_tenant_id)
    end

    def tenant_manager?
      return false unless current_tenant_id
      user.tenant_manager?(current_tenant_id)
    end

    def tenant_admin_or_manager?
      return false unless current_tenant_id
      user.tenant_admin?(current_tenant_id) || user.tenant_manager?(current_tenant_id)
    end

    def target_is_admin?
      return false unless current_tenant_id
      record.tenant_memberships
            .where(tenant_id: current_tenant_id)
            .joins(:role)
            .where(roles: { slug: "tenant_admin" })
            .exists?
    end

    def target_is_primary_admin?
      return false unless current_tenant_id
      record.tenant_memberships
            .where(tenant_id: current_tenant_id, is_primary_admin: true)
            .exists?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        current_tenant_id = ActsAsTenant.current_tenant&.id
        return ::User.none unless current_tenant_id

        if user.tenant_admin?(current_tenant_id) || user.tenant_manager?(current_tenant_id)
          # Usuarios con membresía ACTIVA en el tenant actual
          ::User.joins(:tenant_memberships)
                .where(tenant_memberships: {
                  tenant_id: current_tenant_id,
                  deleted_at: nil
                })
                .distinct
        else
          ::User.none
        end
      end
    end
  end
end
