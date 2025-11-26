# frozen_string_literal: true

# Modelo de Usuario - Identidad base del sistema
# Gestiona TODOS los usuarios: platform admins, tenant users, etc.
#
# Un usuario es único por email en todo el sistema
# Los roles y permisos se gestionan en tablas auxiliares (memberships)

class User < ApplicationRecord
  # ============================================
  # DEVISE MODULES
  # ============================================
  devise :database_authenticatable,
         :recoverable,
         :trackable,
         :lockable,
         :validatable

  # NOTA: NO usamos :registerable porque el registro se hace vía servicios
  # NOTA: NO usamos :confirmable porque usamos email_verified_at custom
  # NOTA: NO usamos :rememberable porque usamos JWT (stateless)

  # ============================================
  # CONCERNS
  # ============================================
  include Auditable       # PaperTrail para auditoría
  include SoftDeletable   # Soft delete con discard

  # NO incluimos Tenantable aquí porque User puede ser cross-tenant
  # La relación con tenants se maneja vía TenantMembership

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


  # ============================================
  # VALIDATIONS
  # ============================================

  # Email
  validates :email,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }

  # Nombres
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }

  # Teléfono (opcional pero con formato)
  validates :phone,
            length: { maximum: 20 },
            format: { with: /\A\+?[\d\s\-\(\)]+\z/, allow_blank: true }

  # Token de invitación único si está presente
  validates :invitation_token, uniqueness: true, allow_nil: true

  # Password solo requerido si no es invitación pendiente
  validates :password,
            presence: true,
            length: { minimum: 8 },
            if: :password_required?

  # ============================================
  # CALLBACKS
  # ============================================

  # Normalizar email antes de validar
  before_validation :normalize_email

  # ============================================
  # SCOPES
  # ============================================

  # Solo usuarios verificados
  scope :verified, -> { where.not(email_verified_at: nil) }
  scope :unverified, -> { where(email_verified_at: nil) }

  # Invitaciones pendientes
  scope :pending_invitation, -> { where.not(invitation_token: nil).where(invitation_accepted_at: nil) }
  scope :invitation_accepted, -> { where.not(invitation_accepted_at: nil) }

  # Por nombre
  scope :by_name, -> { order(:first_name, :last_name) }
  scope :search_by_name, ->(query) {
    where("LOWER(first_name) LIKE :query OR LOWER(last_name) LIKE :query OR LOWER(email) LIKE :query",
          query: "%#{query.downcase}%")
  }

  # Activos (no soft deleted)
  scope :active, -> { kept }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Nombre completo
  def full_name
    "#{first_name} #{last_name}".strip
  end

  # Nombre completo con email
  def display_name
    "#{full_name} (#{email})"
  end

  # Iniciales
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

  # Verificar si es admin de plataforma
  def platform_admin?
    platform_membership.present? && !platform_membership.deleted?
  end

  # Verificar si es super admin
  def super_admin?
    platform_membership&.super_admin? || false
  end

  # Verificar si es support admin
  def support_admin?
    platform_membership&.support_admin? || false
  end

  # Verificar si tiene acceso a un tenant específico
  def has_tenant_access?(tenant_id)
    # Platform admins tienen acceso a todos los tenants
    true if platform_admin?
  end

  # Verificar si tiene acceso a un tenant específico
  def has_tenant_access?(tenant_id)
    return true if platform_admin? # Platform admins tienen acceso a todos los tenants

    tenant_memberships
      .active
      .where(tenant_id: tenant_id)
      .exists?
  end

  # Obtener el rol del usuario en un tenant específico
  def tenant_role(tenant_id)
    membership = tenant_memberships
                  .active
                  .find_by(tenant_id: tenant_id)

    membership&.role&.slug
  end

  # Verificar si es admin de un tenant
  def tenant_admin?(tenant_id)
    return true if platform_admin? # Platform admins son admin en todos los tenants

    tenant_role(tenant_id) == "tenant_admin"
  end

  # Verificar si es manager de un tenant
  def tenant_manager?(tenant_id)
    return true if platform_admin?

    tenant_role(tenant_id) == "tenant_manager"
  end

  # Verificar si es driver de un tenant
  def tenant_driver?(tenant_id)
    return false if platform_admin?

    tenant_role(tenant_id) == "tenant_driver"
  end

  # Obtener todos los tenant_ids accesibles
  def accessible_tenant_ids
    return Tenant.pluck(:id) if platform_admin? # Platform admins ven todos

    tenant_memberships.active.pluck(:tenant_id).uniq
  end

  # Verificar si tiene acceso multi-tenant (platform o múltiples tenants)
  def multi_tenant_access?
    platform_admin? || active_tenant_memberships.count > 1
  end

  # Contexto actual para políticas
  def current_context
    @current_context ||= if platform_admin?
      "platform"
    elsif default_tenant
      "tenant"
    else
      nil
    end
  end

  # Tenant actual para políticas (si está en contexto tenant)
  def current_tenant_for_policy
    return nil if platform_admin?
    default_tenant
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Buscar por email (case insensitive)
    def find_by_email(email)
      find_by("LOWER(email) = ?", email.downcase)
    end

    # Estadísticas
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

  # Normalizar email (lowercase y strip)
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  # Password requerido solo si no hay invitación pendiente
  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end
end
