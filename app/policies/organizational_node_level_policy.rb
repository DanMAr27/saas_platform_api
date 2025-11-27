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
      if platform_admin?
        scope.all
      elsif ActsAsTenant.current_tenant.present?
        scope.where(tenant_id: ActsAsTenant.current_tenant.id)
      else
        scope.none
      end
    end
  end
end
