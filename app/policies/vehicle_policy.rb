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
        # 1. Base query: Vehículos del tenant
        tenant_vehicles = scope.where(tenant_id: context.id)

        # 2. Acceso Global al Tenant (Admin/Manager)
        # Nota: Si el rol de manager es global, return tenant_vehicles.
        # Si el manager está restringido por nodos, debe caer al paso 3.
        # Asumimos que si tiene scopes de nodo, su acceso manager es limitado a esos nodos.
        if user.tenant_admin?(context.id) || (user.tenant_manager?(context.id) && !user.has_node_scopes?(context.id))
          return tenant_vehicles
        end

        # 3. Construir lista de IDs accesibles (Vehículo directo + Nodos)
        accessible_vehicle_ids = []

        # A. Scopes de Vehículo Específicos
        accessible_vehicle_ids += UserVehicleScope.active
                                                  .where(user_id: user.id, tenant_id: context.id)
                                                  .pluck(:vehicle_id)

        # B. Scopes de Nodo con herencia
        # Obtener nodos donde el usuario tiene acceso (y sus descendientes si aplica)
        accessible_nodes = user.accessible_nodes(context.id)

        if accessible_nodes.any?
          # Obtener vehículos asociados a estos nodos
          # Optimization: Pluck IDs directly
          node_vehicle_ids = tenant_vehicles.where(organizational_node_id: accessible_nodes.select(:id)).pluck(:id)
          accessible_vehicle_ids += node_vehicle_ids
        end

        # 4. Retornar query final
        tenant_vehicles.where(id: accessible_vehicle_ids.uniq)
      else
        scope.none
      end
    end
  end
end
