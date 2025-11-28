# app/policies/user_vehicle_scope_policy.rb

# Política para UserVehicleScope
# Define quién puede gestionar scopes de vehículos

class UserVehicleScopePolicy < ApplicationPolicy
  # ============================================
  # ACCIONES DE LECTURA
  # ============================================

  def index?
    super_admin? || tenant_admin_or_manager?
  end

  def show?
    super_admin? ||
    owner_of_scope? ||
    tenant_admin_or_manager?
  end

  # ============================================
  # ACCIONES DE ESCRITURA
  # ============================================

  def create?
    super_admin? || tenant_admin_or_manager?
  end

  def update?
    super_admin? || tenant_admin_or_manager?
  end

  def destroy?
    super_admin? || tenant_admin_or_manager?
  end

  # ============================================
  # HELPERS PRIVADOS
  # ============================================

  private

  def owner_of_scope?
    record.user_id == user.id
  end

  def belongs_to_current_tenant?
    return false unless context.present?
    record.tenant_id == context.id
  end

  # ============================================
  # SCOPE
  # ============================================

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.super_admin?
        scope.all
      elsif context.present?
        # Ver scopes del tenant actual
        # Admin/Manager: todos los scopes del tenant
        # Usuario normal: solo sus propios scopes
        if user.tenant_admin?(context.id) || user.tenant_manager?(context.id)
          scope.where(tenant_id: context.id)
        else
          scope.where(tenant_id: context.id, user_id: user.id)
        end
      else
        # Sin contexto, solo sus propios scopes
        scope.where(user_id: user.id)
      end
    end
  end
end
