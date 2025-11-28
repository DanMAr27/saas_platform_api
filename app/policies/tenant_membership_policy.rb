# app/policies/tenant_membership_policy.rb

# Política para TenantMembership
# Define quién puede gestionar membresías

class TenantMembershipPolicy < ApplicationPolicy
  # ============================================
  # ACCIONES DE LECTURA
  # ============================================

  def index?
    super_admin? || tenant_admin_or_manager?
  end

  def show?
    super_admin? ||
    owner_of_membership? ||
    tenant_admin_or_manager?
  end

  # ============================================
  # ACCIONES DE ESCRITURA
  # ============================================

  def create?
    super_admin? || tenant_admin?
  end

  def update?
    return true if super_admin?
    return false if record.is_primary_admin? # No modificar primary admin
    return false if owner_of_membership? # No auto-modificar

    tenant_admin?
  end

  def destroy?
    return true if super_admin?
    return false if record.is_primary_admin?
    return false if owner_of_membership?

    tenant_admin?
  end

  # ============================================
  # ACCIONES ESPECÍFICAS
  # ============================================

  def change_role?
    return true if super_admin?
    return false if record.is_primary_admin?
    return false if owner_of_membership?

    tenant_admin?
  end

  def suspend?
    return true if super_admin?
    return false if record.is_primary_admin?
    return false if owner_of_membership?

    tenant_admin?
  end

  def activate?
    super_admin? || tenant_admin?
  end

  def set_as_default?
    super_admin? || owner_of_membership?
  end

  # ============================================
  # HELPERS PRIVADOS
  # ============================================

  private

  def owner_of_membership?
    record.user_id == user.id
  end

  # ============================================
  # SCOPE
  # ============================================

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.super_admin?
        scope.all
      elsif context.present?
        # Ver membresías del tenant actual
        scope.where(tenant_id: context.id)
      else
        # Sin contexto, solo sus propias membresías
        scope.where(user_id: user.id)
      end
    end
  end
end
