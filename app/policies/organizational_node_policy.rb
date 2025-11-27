# app/policies/organizational_node_policy.rb

class OrganizationalNodePolicy < ApplicationPolicy
  def index?
    platform_admin? || tenant_admin_or_manager?
  end

  def show?
    return true if platform_admin?
    return true if tenant_admin_or_manager?
    has_record_tenant_access?
  end

  def create?
    platform_admin? || tenant_admin?
  end

  def update?
    platform_admin? || tenant_admin?
  end

  def destroy?
    platform_admin? || tenant_admin?
  end

  def move?
    platform_admin? || tenant_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if platform_admin?
        # Platform admins ven todo
        scope.all
      elsif ActsAsTenant.current_tenant.present?
        # Usuarios con tenant: solo ven nodos de su tenant
        scope.where(tenant_id: ActsAsTenant.current_tenant.id)
      else
        # Sin tenant = sin acceso
        scope.none
      end
    end
  end
end
