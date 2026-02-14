module Management
  class TenantPolicy < ApplicationPolicy
    def show?
      # Solo ver si es admin/manager dl tenant (el record es el tenant)
      user.tenant_admin?(record.id) || user.tenant_manager?(record.id)
    end

    def update?
      # Solo editar si es admin del tenant
      user.tenant_admin?(record.id)
    end

    # Prohibido para Tenant Admin
    def index?; false; end
    def create?; false; end
    def destroy?; false; end
    def activate?; false; end
    def suspend?; false; end

    class Scope < ApplicationPolicy::Scope
      def resolve
        # Scope no usado realmente en single-resource actions, pero por seguridad:
        # Devolver solo tenants donde el usuario tenga rol
        ::Tenant.where(id: user.active_tenants.select(:id))
      end
    end
  end
end
