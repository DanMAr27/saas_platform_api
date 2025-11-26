# app/policies/user_policy.rb
class UserPolicy < ApplicationPolicy
  def index?
    platform_admin? || tenant_admin_or_manager?
  end

  def show?
    return true if platform_admin?
    return true if owner?

    # Puede ver usuarios del mismo tenant
    context.present? && record.has_tenant_access?(context.id) && tenant_admin_or_manager?
  end

  def create?
    platform_admin? || tenant_admin?
  end

  def update?
    return true if platform_admin?
    return true if owner?

    # Tenant admin puede actualizar usuarios de su tenant
    tenant_admin? && context.present? && record.has_tenant_access?(context.id)
  end

  def destroy?
    return true if platform_admin?
    return false if owner? # No auto-eliminarse

    tenant_admin? && context.present? && record.has_tenant_access?(context.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if platform_admin?
        # Platform admins ven todos (filtrar por tenant en el endpoint)
        scope.all
      elsif context.present?
        # Tenant users ven usuarios con membresía en su tenant
        scope.joins(:tenant_memberships)
             .where(tenant_memberships: {
               tenant_id: context.id,
               status: "active"
             })
             .distinct
      else
        # Sin contexto, solo verse a sí mismo
        scope.where(id: user&.id)
      end
    end
  end
end
