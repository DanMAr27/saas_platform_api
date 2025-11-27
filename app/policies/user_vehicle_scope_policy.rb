# app/policies/user_vehicle_scope_policy.rb

class UserVehicleScopePolicy < ApplicationPolicy
  def index?
    platform_admin? || tenant_admin_or_manager?
  end

  def show?
    return true if platform_admin?
    return true if tenant_admin_or_manager?
    return true if owner?

    false
  end

  def create?
    platform_admin? || tenant_admin_or_manager?
  end

  def destroy?
    platform_admin? || tenant_admin_or_manager?
  end

  private

  def owner?
    record.user_id == user&.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if platform_admin?
        scope.all
      elsif context.present?
        scope.where(tenant_id: context.id)
      else
        scope.where(user_id: user&.id)
      end
    end
  end
end
