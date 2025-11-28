# app/policies/user_policy.rb

# Política para User
# Define quién puede realizar operaciones sobre usuarios

class UserPolicy < ApplicationPolicy
  # ============================================
  # ACCIONES DE LECTURA
  # ============================================

  def index?
    # SuperAdmin puede listar todos los usuarios
    # TenantAdmin/Manager pueden listar usuarios de su tenant
    super_admin? || tenant_admin_or_manager?
  end

  def show?
    # SuperAdmin puede ver cualquier usuario
    # Usuario puede verse a sí mismo
    # TenantAdmin/Manager pueden ver usuarios de su tenant
    super_admin? || owner? || can_view_in_tenant?
  end

  # ============================================
  # ACCIONES DE ESCRITURA
  # ============================================

  def create?
    # SuperAdmin puede crear cualquier usuario
    # TenantAdmin puede crear usuarios en su tenant
    super_admin? || tenant_admin?
  end

  def update?
    # SuperAdmin puede actualizar cualquier usuario
    # Usuario puede actualizar su propio perfil
    # TenantAdmin puede actualizar usuarios de su tenant
    super_admin? || owner? || (tenant_admin? && can_view_in_tenant?)
  end

  def destroy?
    # SuperAdmin puede eliminar cualquier usuario
    # TenantAdmin puede eliminar usuarios de su tenant (excepto primary admin)
    return true if super_admin?
    return false unless tenant_admin?
    return false if is_primary_admin_in_tenant?

    can_view_in_tenant?
  end

  # ============================================
  # ACCIONES ESPECÍFICAS DE GESTIÓN DE USUARIOS
  # ============================================

  def invite?
    create?
  end

  def resend_invitation?
    super_admin? || tenant_admin_or_manager?
  end

  def activate?
    super_admin? || tenant_admin?
  end

  def suspend?
    return false if owner? # No puede suspenderse a sí mismo
    return true if super_admin?
    return false unless tenant_admin?
    return false if is_primary_admin_in_tenant?

    can_view_in_tenant?
  end

  def change_role?
    return false if is_primary_admin_in_tenant? # No cambiar rol del primary admin
    super_admin? || tenant_admin?
  end

  def manage_scopes?
    super_admin? || tenant_admin_or_manager?
  end

  def remove_from_tenant?
    return true if super_admin?
    return false unless tenant_admin?
    return false if is_primary_admin_in_tenant?
    return false if owner? # No puede removerse a sí mismo

    can_view_in_tenant?
  end

  def view_scopes?
    super_admin? || owner? || tenant_admin_or_manager?
  end

  def impersonate?
    # Solo SupportAdmin puede impersonar
    support_admin? && user.platform_membership&.can_impersonate?
  end

  def view_audit_log?
    super_admin? || owner? || tenant_admin?
  end

  # ============================================
  # HELPERS PRIVADOS
  # ============================================

  private

  def can_view_in_tenant?
    return false unless context.present?

    # Verificar si el usuario tiene membresía en el tenant actual
    record.tenant_memberships
          .active
          .exists?(tenant_id: context.id)
  end

  def is_primary_admin_in_tenant?
    return false unless context.present?

    record.tenant_memberships
          .active
          .exists?(tenant_id: context.id, is_primary_admin: true)
  end

  # ============================================
  # SCOPE
  # ============================================

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.super_admin?
        # SuperAdmin ve todos los usuarios
        scope.all
      elsif context.present?
        # En contexto de tenant, ver usuarios del tenant
        scope.joins(:tenant_memberships)
             .where(tenant_memberships: {
               tenant_id: context.id,
               status: "active"
             })
             .where(tenant_memberships: { deleted_at: nil })
             .distinct
      else
        # Sin contexto, solo verse a sí mismo
        scope.where(id: user.id)
      end
    end
  end
end
