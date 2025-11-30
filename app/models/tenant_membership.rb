# app/models/tenant_membreship.rb

# Modelo TenantMembership
# Relaciona un User con un Tenant y define UN rol específico dentro del tenant
# IMPORTANTE: Un usuario puede tener MÚLTIPLES membresías (roles) en el mismo tenant
# Ejemplo: John puede ser 'manager' Y 'driver' en el tenant Acme Corp
#          Esto se logra creando 2 registros TenantMembership separados

class TenantMembership < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable       # PaperTrail
  include SoftDeletable   # Soft delete

  # ============================================
  # ENUMS Y CONSTANTES
  # ============================================

  # Estados de la membresía
  STATUSES = %w[invited active suspended].freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================

  belongs_to :user
  belongs_to :tenant
  belongs_to :role
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  # ============================================
  # DELEGATIONS
  # ============================================

  delegate :slug, :name, to: :role, prefix: true, allow_nil: true
  delegate :context, to: :role, prefix: true, allow_nil: true

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :user_id, presence: true
  validates :tenant_id, presence: true
  validates :role_id, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  # CLAVE: Un usuario NO puede tener el mismo rol DOS VECES en un tenant
  # Pero SÍ puede tener DIFERENTES roles en el mismo tenant
  validates :role_id,
            uniqueness: {
              scope: [ :user_id, :tenant_id ],
              conditions: -> { where(deleted_at: nil) },
              message: "already assigned to this user in this tenant"
            }

  # Solo puede haber un primary admin por tenant
  # (independiente de cuántos roles tenga el usuario)
  validates :is_primary_admin,
            uniqueness: {
              scope: :tenant_id,
              conditions: -> { where(is_primary_admin: true, deleted_at: nil) },
              message: "only one primary admin allowed per tenant"
            },
            if: :is_primary_admin?

  # Token de invitación único
  validates :invitation_token,
            uniqueness: true,
            allow_nil: true

  # Solo un tenant por defecto por usuario
  validates :is_default,
            uniqueness: {
              scope: :user_id,
              conditions: -> { where(is_default: true, deleted_at: nil) },
              message: "user can only have one default tenant"
            },
            if: :is_default?

  # Validación custom: no se puede cambiar tenant_id
  validate :tenant_id_immutable, on: :update

  # Validación: el rol debe ser de contexto tenant
  validate :role_must_be_tenant_context

  # ============================================
  # CALLBACKS
  # ============================================

  before_validation :set_default_status, if: :new_record?
  before_create :generate_invitation_token, if: -> { status == "invited" }
  after_create :set_as_default_if_first_membership

  # ============================================
  # SCOPES
  # ============================================

  scope :active, -> { where(status: "active") }
  scope :invited, -> { where(status: "invited") }
  scope :suspended, -> { where(status: "suspended") }

  scope :with_role_slug, ->(slug) { joins(:role).where(roles: { slug: slug }) }
  scope :admins, -> { with_role_slug("tenant_admin") }
  scope :managers, -> { with_role_slug("tenant_manager") }
  scope :drivers, -> { with_role_slug("tenant_driver") }

  scope :primary_admins, -> { where(is_primary_admin: true) }
  scope :default_memberships, -> { where(is_default: true) }

  scope :pending_invitations, -> {
    invited.where.not(invitation_token: nil).where(invitation_accepted_at: nil)
  }

  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_tenant, ->(tenant_id) { where(tenant_id: tenant_id) }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Estado
  def active?
    status == "active"
  end

  def invited?
    status == "invited"
  end

  def suspended?
    status == "suspended"
  end

  # Roles - usando delegation de role_slug
  def admin?
    role_slug == "tenant_admin"
  end

  def manager?
    role_slug == "tenant_manager"
  end

  def driver?
    role_slug == "tenant_driver"
  end

  # Invitación
  def invitation_pending?
    invited? && invitation_token.present? && invitation_accepted_at.nil?
  end

  def invitation_expired?
    return false unless invitation_pending?
    return false unless invitation_sent_at.present?

    invitation_sent_at < 7.days.ago
  end

  def accept_invitation!
    return false unless invitation_pending?

    update!(
      status: "active",
      invitation_accepted_at: Time.current,
      invitation_token: nil
    )
  end

  def resend_invitation!
    return false unless invited?

    generate_invitation_token
    update!(invitation_sent_at: Time.current)
  end

  # Activación y suspensión
  def activate!
    update!(status: "active")
  end

  def suspend!
    update!(status: "suspended")
  end

  # Default membership
  def set_as_default!
    # Remover default de otras membresías del mismo usuario
    TenantMembership.where(user_id: user_id, is_default: true)
                    .where.not(id: id)
                    .update_all(is_default: false)

    update!(is_default: true)
  end

  # Display
  def display_name
    "#{user.full_name} - #{role_name} at #{tenant.name}"
  end

  def to_s
    display_name
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Slugs de roles disponibles para tenant
    def available_role_slugs
      Role.tenant_roles.pluck(:slug)
    end

    # Roles disponibles para tenant (objetos completos)
    def available_roles
      Role.tenant_roles.by_priority
    end

    # Encontrar membresía por token de invitación
    def find_by_invitation_token(token)
      find_by(invitation_token: token, status: "invited")
    end

    # Estadísticas
    def stats_for_tenant(tenant_id)
      where(tenant_id: tenant_id).group(:status).count
    end

    def stats_for_user(user_id)
      where(user_id: user_id).group(:status).count
    end

    # Estadísticas por rol
    def role_distribution_for_tenant(tenant_id)
      where(tenant_id: tenant_id)
        .joins(:role)
        .group("roles.name")
        .count
    end

    # Obtener todos los roles de un usuario en un tenant
    # Retorna un array de Role objects
    def roles_for_user_in_tenant(user_id, tenant_id)
      where(user_id: user_id, tenant_id: tenant_id)
        .active
        .includes(:role)
        .map(&:role)
    end

    # Verificar si un usuario tiene un rol específico en un tenant
    def user_has_role?(user_id, tenant_id, role_slug)
      joins(:role)
        .where(user_id: user_id, tenant_id: tenant_id)
        .where(roles: { slug: role_slug })
        .active
        .exists?
    end

    # Obtener slugs de roles de un usuario en un tenant
    def role_slugs_for_user_in_tenant(user_id, tenant_id)
      joins(:role)
        .where(user_id: user_id, tenant_id: tenant_id)
        .active
        .pluck("roles.slug")
    end
  end

  private

  # ============================================
  # PRIVATE METHODS
  # ============================================

  # Generar token de invitación
  def generate_invitation_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
    self.invitation_sent_at = Time.current
  end

  # Estado por defecto
  def set_default_status
    self.status ||= "invited"
  end

  # Establecer como default si es la primera membresía del usuario
  def set_as_default_if_first_membership
    return if user.tenant_memberships.active.count > 1

    set_as_default!
  end

  # Validación: tenant_id no puede cambiar
  def tenant_id_immutable
    if tenant_id_changed? && persisted?
      errors.add(:tenant_id, "cannot be changed")
    end
  end

  # Validación: el rol debe ser de contexto tenant
  def role_must_be_tenant_context
    return if role.nil?

    unless role.tenant_role?
      errors.add(:role, "must be a tenant role")
    end
  end
end
