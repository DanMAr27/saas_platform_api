# app/policies/organizational_node_level_policy.rb

class OrganizationalNodeLevelPolicy < ApplicationPolicy
  def index?
    platform_admin? || tenant_admin_or_manager?
  end

  def show?
    platform_admin? || tenant_admin_or_manager?
  end

  def create?
    platform_admin? || tenant_admin?
  end

  def update?
    return true if platform_admin?
    tenant_admin? && !record.is_system?
  end

  def destroy?
    return false if record.is_system?
    return false if record.has_nodes?
    platform_admin? || tenant_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.platform_admin?
        # Platform admin: usar el context (tenant) si está presente
        if context.present?
          scope.where(tenant_id: context.id)
        else
          scope.all
        end
      elsif context.present?
        # Tenant user: usar el context (su tenant)
        scope.where(tenant_id: context.id)
      else
        # Sin context = sin acceso
        scope.none
      end
    end
  end
end
