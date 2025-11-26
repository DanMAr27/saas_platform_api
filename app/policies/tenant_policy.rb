# app/policies/tenant_policy.rb
class TenantPolicy < ApplicationPolicy
  def index?
    # Platform admins pueden listar todos
    # Tenant users pueden listar sus tenants
    super_admin? || user.present?
  end

  def show?
    # Platform admins pueden ver cualquier tenant
    # Tenant users pueden ver tenants donde tienen membresía
    super_admin? || user&.has_tenant_access?(record.id)
  end

  def create?
    super_admin?
  end

  def update?
    # SuperAdmin o TenantAdmin del tenant específico
    super_admin? || (user&.tenant_admin?(record.id) && user.has_tenant_access?(record.id))
  end

  def destroy?
    super_admin?
  end

  def activate?
    super_admin?
  end

  def suspend?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.super_admin?
        ::Tenant.all
      elsif user.present?
        ::Tenant
          .joins(:tenant_memberships)
          .where(tenant_memberships: {
            user_id: user.id,
            status: "active"
          })
          .distinct
      else
        ::Tenant.none
      end
    end
  end
end
