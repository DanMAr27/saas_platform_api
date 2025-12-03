# app/models/user.rb

# Modelo de Usuario - Identidad base del sistema
# Gestiona TODOS los usuarios: platform admins, tenant users, etc.
# Un usuario puede tener múltiples roles en múltiples tenants

class User < ApplicationRecord
  # ============================================
  # DEVISE MODULES
  # ============================================
  devise :database_authenticatable,
         :recoverable,
         :trackable,
         :lockable,
         :validatable

  # ============================================
  # CONCERNS
  # ============================================
  include Auditable
  include SoftDeletable

  # ============================================
  # ASSOCIATIONS
  # ============================================

  # Invitaciones
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :invited_users, class_name: "User", foreign_key: :invited_by_id, dependent: :nullify

  # Relaciones con contextos
  has_one :platform_membership, dependent: :destroy
  has_many :tenant_memberships, dependent: :destroy
  has_many :tenants, through: :tenant_memberships

  # Membresías activas
  has_many :active_tenant_memberships,
           -> { active },
           class_name: "TenantMembership"
  has_many :active_tenants, through: :active_tenant_memberships, source: :tenant

  # Tenant por defecto
  has_one :default_tenant_membership,
          -> { where(is_default: true, status: "active") },
          class_name: "TenantMembership"
  has_one :default_tenant, through: :default_tenant_membership, source: :tenant


  has_many :user_node_scopes, dependent: :destroy
  has_many :user_vehicle_scopes, dependent: :destroy

  # Nodos accesibles a través de scopes
  has_many :accessible_organizational_nodes,
           through: :user_node_scopes,
           source: :organizational_node

  # Vehículos accesibles a través de scopes
  has_many :accessible_vehicles,
           through: :user_vehicle_scopes,
           source: :vehicle

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }

  validates :phone,
            length: { maximum: 20 },
            format: { with: /\A\+?[\d\s\-\(\)]+\z/, allow_blank: true }

  validates :invitation_token, uniqueness: true, allow_nil: true

  validates :password,
            presence: true,
            length: { minimum: 8 },
            if: :password_required?

  # ============================================
  # CALLBACKS
  # ============================================

  before_validation :normalize_email

  # ============================================
  # SCOPES
  # ============================================

  scope :verified, -> { where.not(email_verified_at: nil) }
  scope :unverified, -> { where(email_verified_at: nil) }
  scope :pending_invitation, -> { where.not(invitation_token: nil).where(invitation_accepted_at: nil) }
  scope :invitation_accepted, -> { where.not(invitation_accepted_at: nil) }
  scope :by_name, -> { order(:first_name, :last_name) }
  scope :search_by_name, ->(query) {
    where("LOWER(first_name) LIKE :query OR LOWER(last_name) LIKE :query OR LOWER(email) LIKE :query",
          query: "%#{query.downcase}%")
  }
  scope :active, -> { kept }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Nombre completo
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def display_name
    "#{full_name} (#{email})"
  end

  def initials
    "#{first_name[0]}#{last_name[0]}".upcase
  end

  # Verificar email
  def verify_email!
    update_column(:email_verified_at, Time.current)
  end

  def email_verified?
    email_verified_at.present?
  end

  # Invitaciones
  def invitation_pending?
    invitation_token.present? && invitation_accepted_at.nil?
  end

  def invitation_expired?
    invitation_expires_at.present? && invitation_expires_at < Time.current
  end

  def accept_invitation!
    update!(
      invitation_accepted_at: Time.current,
      invitation_token: nil,
      invitation_expires_at: nil,
      email_verified_at: Time.current
    )
  end

  # Estado de la cuenta
  def active?
    !deleted? && !locked_at.present?
  end

  def locked?
    locked_at.present?
  end

  # ============================================
  # MULTI-ROL HELPERS
  # ============================================

  # Obtener todos los roles de un usuario en un tenant específico
  # Retorna array de Role objects
  def roles_in_tenant(tenant)
    tenant_id = tenant.is_a?(Tenant) ? tenant.id : tenant
    TenantMembership.roles_for_user_in_tenant(id, tenant_id)
  end

  # Obtener slugs de roles en un tenant
  # Retorna array de strings ['tenant_admin', 'tenant_manager']
  def role_slugs_in_tenant(tenant)
    tenant_id = tenant.is_a?(Tenant) ? tenant.id : tenant
    TenantMembership.role_slugs_for_user_in_tenant(id, tenant_id)
  end

  # Verificar si tiene un rol específico en un tenant
  def has_role_in_tenant?(role_slug, tenant)
    tenant_id = tenant.is_a?(Tenant) ? tenant.id : tenant
    TenantMembership.user_has_role?(id, tenant_id, role_slug)
  end

  # Verificar si tiene CUALQUIERA de los roles en un tenant
  def has_any_role_in_tenant?(role_slugs, tenant)
    tenant_id = tenant.is_a?(Tenant) ? tenant.id : tenant
    user_roles = role_slugs_in_tenant(tenant_id)
    (user_roles & Array(role_slugs)).any?
  end

  # Verificar si tiene TODOS los roles en un tenant
  def has_all_roles_in_tenant?(role_slugs, tenant)
    tenant_id = tenant.is_a?(Tenant) ? tenant.id : tenant
    user_roles = role_slugs_in_tenant(tenant_id)
    (Array(role_slugs) - user_roles).empty?
  end

  # Obtener el rol de mayor prioridad en un tenant
  def primary_role_in_tenant(tenant)
    roles_in_tenant(tenant).min_by(&:priority)
  end

  # Verificar permisos específicos
  def admin_in_tenant?(tenant)
    has_role_in_tenant?("tenant_admin", tenant)
  end

  def manager_in_tenant?(tenant)
    has_role_in_tenant?("tenant_manager", tenant)
  end

  def driver_in_tenant?(tenant)
    has_role_in_tenant?("tenant_driver", tenant)
  end

  # Verificar si puede gestionar (admin o manager)
  def can_manage_in_tenant?(tenant)
    has_any_role_in_tenant?([ "tenant_admin", "tenant_manager" ], tenant)
  end

  # ============================================
  # PLATFORM ADMIN HELPERS
  # ============================================

  # Verificar si el usuario es Platform Admin
  def platform_admin?
    platform_membership.present? &&
    !platform_membership.deleted? &&
    platform_membership.role.present?
  end

  # Verificar si el usuario es Super Admin
  def super_admin?
    platform_admin? && platform_membership.role.super_admin?
  end

  # Verificar si el usuario es Support Admin
  def support_admin?
    platform_admin? && platform_membership.role.support_admin?
  end

  # ============================================
  # TENANT ACCESS HELPERS
  # ============================================

  # Verificar si el usuario tiene acceso a un tenant específico
  def has_tenant_access?(tenant_id)
    tenant_memberships
      .where(state: [ "active", "invited" ])
      .kept
      .exists?(tenant_id: tenant_id)
  end

  # Obtener rol del usuario en un tenant específico
  def tenant_role(tenant_id)
    membership = tenant_memberships
                  .active
                  .kept
                  .find_by(tenant_id: tenant_id)

    return nil unless membership
    membership.role&.slug || membership.role
  end

  def tenants_with_role(role_slug)
    tenant_memberships
      .active
      .joins(:role)
      .where(roles: { slug: role_slug })
      .includes(:tenant)
      .map(&:tenant)
  end

  # Verificar si es admin de un tenant
  def tenant_admin?(tenant_id)
    membership = tenant_memberships
                  .active
                  .kept
                  .includes(:role)
                  .find_by(tenant_id: tenant_id)

    return false unless membership
    membership.role&.tenant_admin? || membership.role == "admin"
  end

  # Verificar si es manager de un tenant
  def tenant_manager?(tenant_id)
    membership = tenant_memberships
                  .active
                  .kept
                  .includes(:role)
                  .find_by(tenant_id: tenant_id)

    return false unless membership
    membership.role&.tenant_manager? || membership.role == "manager"
  end

  # Verificar si es driver de un tenant
  def tenant_driver?(tenant_id)
    membership = tenant_memberships
                  .active
                  .kept
                  .includes(:role)
                  .find_by(tenant_id: tenant_id)

    return false unless membership
    membership.role&.tenant_driver? || membership.role == "driver"
  end

  # Verificar si es admin o manager de un tenant
  def tenant_admin_or_manager?(tenant_id)
    tenant_admin?(tenant_id) || tenant_manager?(tenant_id)
  end

  # Obtener resumen de accesos del usuario
  def access_summary
    {
      platform_admin: platform_admin?,
      super_admin: super_admin?,
      support_admin: support_admin?,
      total_tenants: active_tenants.count,
      default_tenant: default_tenant&.name,
      tenant_roles: active_tenant_memberships.includes(:tenant, :role).map do |m|
        {
          tenant: m.tenant.name,
          role: m.role.name,
          status: m.status
        }
      end
    }
  end

  # Obtener todos los roles del usuario (platform + tenants)
  def all_roles
    roles = []

    # Rol de plataforma
    if platform_membership.present?
      roles << {
        context: "platform",
        role_slug: platform_membership.role.slug,
        role_name: platform_membership.role.name
      }
    end

    # Roles de tenants
    tenant_memberships.active.kept.includes(:role, :tenant).each do |membership|
      roles << {
        context: "tenant",
        tenant_id: membership.tenant_id,
        tenant_name: membership.tenant.name,
        role_slug: membership.role&.slug || membership.role,
        role_name: membership.role&.name || membership.role.titleize
      }
    end

    roles
  end

  # Obtener todos los tenants del usuario
  def accessible_tenants
    active_tenants.kept.where(status: "active")
  end

  # Verificar si el usuario tiene múltiples contextos
  def multiple_contexts?
    all_roles.size > 1
  end

  # Verificar si el usuario tiene acceso a un nodo organizacional
  def has_node_access?(node_id, tenant_id = nil)
    query = user_node_scopes.kept
    query = query.where(tenant_id: tenant_id) if tenant_id.present?

    # Verificar acceso directo
    return true if query.exists?(organizational_node_id: node_id)

    # Verificar acceso por jerarquía (si tiene acceso a padre con include_children)
    node = OrganizationalNode.find_by(id: node_id)
    return false unless node

    query.where(include_children: true).any? do |scope|
      node.ancestor_of?(scope.organizational_node)
    end
  end

  # Verificar si el usuario tiene acceso a un vehículo
  def has_vehicle_access?(vehicle_id, tenant_id = nil)
    query = user_vehicle_scopes.kept.active
    query = query.where(tenant_id: tenant_id) if tenant_id.present?

    query.exists?(vehicle_id: vehicle_id)
  end

  # Obtener todos los nodos accesibles para el usuario en un tenant
  def accessible_nodes(tenant_id)
    node_scopes = user_node_scopes
                    .kept
                    .where(tenant_id: tenant_id)
                    .includes(:organizational_node)

    accessible_node_ids = []

    node_scopes.each do |scope|
      if scope.include_children?
        # Incluir el nodo y todos sus descendientes
        accessible_node_ids << scope.organizational_node_id
        accessible_node_ids += scope.organizational_node.descendants.pluck(:id)
      else
        # Solo el nodo específico
        accessible_node_ids << scope.organizational_node_id
      end
    end

    OrganizationalNode.where(id: accessible_node_ids.uniq)
  end

  # Obtener todos los vehículos accesibles para el usuario en un tenant
  def accessible_vehicles(tenant_id)
    vehicle_ids = user_vehicle_scopes
                    .kept
                    .active
                    .where(tenant_id: tenant_id)
                    .pluck(:vehicle_id)

    Vehicle.where(id: vehicle_ids)
  end

  # Estadísticas de scopes del usuario en un tenant
  def scopes_stats(tenant_id)
    {
      node_scopes: user_node_scopes.kept.where(tenant_id: tenant_id).count,
      vehicle_scopes: user_vehicle_scopes.kept.where(tenant_id: tenant_id).count,
      active_vehicle_scopes: user_vehicle_scopes.kept.active.where(tenant_id: tenant_id).count,
      expired_vehicle_scopes: user_vehicle_scopes.kept.expired.where(tenant_id: tenant_id).count
    }
  end

  # Verificar si puede gestionar usuarios en un tenant
  def can_manage_users_in_tenant?(tenant_id)
    super_admin? || tenant_admin?(tenant_id)
  end

  # Verificar si puede gestionar scopes en un tenant
  def can_manage_scopes_in_tenant?(tenant_id)
    super_admin? || tenant_admin_or_manager?(tenant_id)
  end

  # Verificar si puede ver información de un tenant
  def can_view_tenant?(tenant_id)
    super_admin? || has_tenant_access?(tenant_id)
  end

  # Verificar si puede modificar un tenant
  def can_modify_tenant?(tenant_id)
    super_admin? || tenant_admin?(tenant_id)
  end

  # Información completa del contexto actual del usuario
  def context_info(tenant_id = nil)
    info = {
      user_id: id,
      email: email,
      full_name: full_name,
      is_platform_admin: platform_admin?,
      is_super_admin: super_admin?,
      is_support_admin: support_admin?
    }

    if tenant_id.present?
      membership = tenant_memberships
                    .active
                    .kept
                    .includes(:role)
                    .find_by(tenant_id: tenant_id)

      if membership
        info[:tenant_context] = {
          tenant_id: tenant_id,
          role_slug: membership.role&.slug || membership.role,
          role_name: membership.role&.name || membership.role.titleize,
          is_primary_admin: membership.is_primary_admin?,
          is_default: membership.is_default?
        }
      end
    end

    info
  end

  # Resumen de accesos del usuario
  def access_summary
    {
      platform_access: platform_admin?,
      tenant_count: tenant_memberships.active.kept.count,
      roles: all_roles,
      default_tenant: default_tenant&.name
    }
  end


  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    def find_by_email(email)
      find_by("LOWER(email) = ?", email.downcase)
    end

    def stats
      {
        total: count,
        verified: verified.count,
        unverified: unverified.count,
        pending_invitations: pending_invitation.count,
        locked: where.not(locked_at: nil).count,
        deleted: discarded.count
      }
    end
  end

  private

  # ============================================
  # PRIVATE METHODS
  # ============================================

  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end
end
