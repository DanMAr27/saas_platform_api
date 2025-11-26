# app/policies/tenant_membership_policy.rb
class TenantMembershipPolicy < ApplicationPolicy
  def index?
    # Platform admins ven todas las memberships
    # Tenant admins/managers ven las de su tenant
    platform_admin? || tenant_admin_or_manager?
  end

  def show?
    return true if platform_admin?
    return true if owner? # Ver propia membresía

    # Tenant admin/manager puede ver memberships de su tenant
    tenant_admin_or_manager? && record.tenant_id == context&.id
  end

  def create?
    # Platform admins pueden crear en cualquier tenant
    # Tenant admins pueden crear en su tenant
    platform_admin? || (tenant_admin? && record.tenant_id == context&.id)
  end

  def update?
    return true if platform_admin?
    return false if record.is_primary_admin? # No se puede modificar primary admin

    # Tenant admin puede modificar memberships de su tenant
    tenant_admin? && record.tenant_id == context&.id
  end

  def destroy?
    return true if platform_admin?
    return false if record.is_primary_admin?
    return false if record.user_id == user&.id # No auto-eliminarse

    tenant_admin? && record.tenant_id == context&.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if platform_admin?
        # Platform admins ven todas (filtrar por tenant en el endpoint)
        scope.all
      elsif context.present?
        # Tenant users solo ven memberships de su tenant
        scope.where(tenant_id: context.id)
      else
        # Sin contexto, solo ver propias memberships
        scope.where(user_id: user&.id)
      end
    end
  end
end
