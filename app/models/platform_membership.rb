# frozen_string_literal: true

# Modelo PlatformMembership
# Define usuarios con acceso de nivel plataforma (SuperAdmin, SupportAdmin)
# Estos usuarios operan sobre todos los tenants

class PlatformMembership < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable       # PaperTrail
  include SoftDeletable   # Soft delete

  # ============================================
  # ASSOCIATIONS
  # ============================================

  belongs_to :user
  belongs_to :role
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :user_id, presence: true, uniqueness: {
    conditions: -> { where(deleted_at: nil) },
    message: "already has a platform membership"
  }
  validates :role_id, presence: true
  validates :context, presence: true, inclusion: { in: [ "platform" ] }

  # Validar que el rol sea de contexto platform
  validate :role_must_be_platform_context

  # MFA requerido para ciertos roles
  validate :mfa_required_for_support, if: :support_admin?

  # ============================================
  # CALLBACKS
  # ============================================

  after_create :notify_platform_membership_created
  before_destroy :prevent_last_super_admin_deletion

  # ============================================
  # SCOPES
  # ============================================

  scope :super_admins, -> { joins(:role).where(roles: { slug: "super_admin" }) }
  scope :support_admins, -> { joins(:role).where(roles: { slug: "support_admin" }) }
  scope :with_mfa, -> { where(mfa_enabled: true) }
  scope :without_mfa, -> { where(mfa_enabled: false) }
  scope :can_impersonate, -> { where(can_impersonate: true) }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Verificar tipo de rol
  def super_admin?
    role.super_admin?
  end

  def support_admin?
    role.support_admin?
  end

  # MFA
  def mfa_configured?
    mfa_enabled? && mfa_configured_at.present?
  end

  def configure_mfa!
    update!(
      mfa_enabled: true,
      mfa_configured_at: Time.current
    )
  end

  def disable_mfa!
    update!(
      mfa_enabled: false,
      mfa_configured_at: nil
    )
  end

  # Impersonación
  def can_impersonate?
    can_impersonate && (super_admin? || support_admin?)
  end

  def record_impersonation!
    update_column(:last_impersonation_at, Time.current)
  end

  # IP permitidas
  def ip_allowed?(ip)
    return true if allowed_ips.blank? || allowed_ips.empty?

    allowed_ips.include?(ip)
  end

  def add_allowed_ip(ip)
    update!(allowed_ips: (allowed_ips + [ ip ]).uniq)
  end

  def remove_allowed_ip(ip)
    update!(allowed_ips: allowed_ips - [ ip ])
  end

  # Display
  def display_name
    "#{user.full_name} - #{role.name}"
  end

  def to_s
    display_name
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Verificar si un usuario es platform admin
    def exists_for_user?(user_id)
      exists?(user_id: user_id)
    end

    # Contar super admins activos
    def super_admin_count
      super_admins.kept.count
    end

    # Estadísticas
    def stats
      {
        total: kept.count,
        super_admins: super_admins.kept.count,
        support_admins: support_admins.kept.count,
        with_mfa: with_mfa.count,
        can_impersonate: can_impersonate.count
      }
    end
  end

  private

  # ============================================
  # PRIVATE METHODS
  # ============================================

  # Validar que el rol sea de contexto platform
  def role_must_be_platform_context
    if role.present? && !role.platform_role?
      errors.add(:role, "must be a platform role")
    end
  end

  # MFA requerido para support admins
  def mfa_required_for_support
    if support_admin? && !mfa_enabled?
      errors.add(:mfa_enabled, "is required for Support Admin role")
    end
  end

  # Prevenir eliminación del último super admin
  def prevent_last_super_admin_deletion
    if super_admin? && PlatformMembership.super_admin_count <= 1
      errors.add(:base, "Cannot delete the last Super Admin")
      throw :abort
    end
  end

  # Notificar creación (para enviar email, logs, etc.)
  def notify_platform_membership_created
    Rails.logger.info("[PlatformMembership] Created: #{display_name}")
    # TODO: Enviar email de notificación
  end
end
