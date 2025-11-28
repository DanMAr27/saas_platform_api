# app/policies/role_policy.rb

# Política para Role
# Define quién puede gestionar roles

class RolePolicy < ApplicationPolicy
  # ============================================
  # ACCIONES DE LECTURA
  # ============================================

  def index?
    # Todos los usuarios autenticados pueden ver roles disponibles
    user.present?
  end

  def show?
    # Todos los usuarios autenticados pueden ver detalles de roles
    user.present?
  end

  # ============================================
  # ACCIONES DE ESCRITURA
  # ============================================

  def create?
    # Solo SuperAdmin puede crear roles
    super_admin?
  end

  def update?
    # Solo SuperAdmin puede actualizar roles
    # No se pueden actualizar roles del sistema
    super_admin? && !record.is_system?
  end

  def destroy?
    # Solo SuperAdmin puede eliminar roles
    # No se pueden eliminar roles del sistema
    super_admin? && !record.is_system?
  end

  # ============================================
  # ACCIONES ESPECÍFICAS
  # ============================================

  def view_usage_stats?
    super_admin?
  end

  # ============================================
  # SCOPE
  # ============================================

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.super_admin?
        # SuperAdmin ve todos los roles
        scope.all
      elsif context.present?
        # En contexto de tenant, ver solo roles de tenant
        scope.where(context: "tenant")
      else
        # Sin contexto, ver roles según acceso del usuario
        if user.platform_membership.present?
          scope.where(context: "platform")
        else
          scope.where(context: "tenant")
        end
      end
    end
  end
end
