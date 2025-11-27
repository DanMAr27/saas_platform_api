# app/policies/vehicle_policy.rb

class VehiclePolicy < ApplicationPolicy
  def index?
    platform_admin? || tenant_admin_or_manager?
  end

  def show?
    return true if platform_admin?
    return true if tenant_admin_or_manager?

    # Usuario puede ver vehículos a los que tiene scope
    user&.user_vehicle_scopes&.active&.exists?(vehicle_id: record.id)
  end

  def create?
    platform_admin? || tenant_admin_or_manager?
  end

  def update?
    return true if platform_admin?
    return true if tenant_admin?

    # Manager puede actualizar vehículos de su tenant
    tenant_admin_or_manager? && has_record_tenant_access?
  end

  def destroy?
    platform_admin? || tenant_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if platform_admin?
        scope.all
      elsif context.present?
        # Obtener vehículos del tenant
        tenant_vehicles = scope.where(tenant_id: context.id)

        # Si no es admin/manager, filtrar por scopes
        if user.tenant_admin?(context.id) || user.tenant_manager?(context.id)
          tenant_vehicles
        else
          vehicle_ids = UserVehicleScope.active.where(user_id: user.id).pluck(:vehicle_id)
          tenant_vehicles.where(id: vehicle_ids)
        end
      else
        scope.none
      end
    end
  end
end
