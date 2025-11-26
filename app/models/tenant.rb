# frozen_string_literal: true

# Modelo de Tenant (Organización/Cliente)
# Representa un espacio aislado con sus propios usuarios, datos y configuración
#
# Cada tenant es una organización cliente que usa la plataforma
# Los datos entre tenants están completamente aislados

class Tenant < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable       # PaperTrail
  include SoftDeletable   # Soft delete

  # ============================================
  # ENUMS Y CONSTANTES
  # ============================================

  # Estados posibles del tenant
  STATUSES = %w[trial active suspended cancelled].freeze

  # Planes disponibles
  PLANS = %w[trial basic professional enterprise].freeze

  # Configuración de límites por plan
  PLAN_LIMITS = {
    "trial" => { max_users: 5, max_storage_gb: 10 },
    "basic" => { max_users: 10, max_storage_gb: 50 },
    "professional" => { max_users: 50, max_storage_gb: 200 },
    "enterprise" => { max_users: 1000, max_storage_gb: 1000 }
  }.freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================

  # Usuario que creó el tenant
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  # Membresías (usuarios del tenant)
  has_many :tenant_memberships, dependent: :destroy
  has_many :users, through: :tenant_memberships

  # Admin principal del tenant
  has_one :primary_membership,
          -> { where(is_primary_admin: true) },
          class_name: "TenantMembership"
  has_one :primary_admin, through: :primary_membership, source: :user

  # Usuarios activos
  has_many :active_memberships,
           -> { where(status: "active") },
           class_name: "TenantMembership"
  has_many :active_users, through: :active_memberships, source: :user

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { maximum: 100 },
            format: {
              with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
              message: "only allows lowercase letters, numbers, and hyphens"
            }

  validates :domain,
            uniqueness: { case_sensitive: false, allow_nil: true },
            format: {
              with: /\A[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,}\z/i,
              allow_blank: true,
              message: "must be a valid domain"
            }

  validates :status, inclusion: { in: STATUSES }
  validates :plan, inclusion: { in: PLANS }

  validates :country,
            length: { is: 2 },
            format: { with: /\A[A-Z]{2}\z/, message: "must be ISO 3166-1 alpha-2 code" },
            if: -> { country.present? }

  validates :currency,
            length: { is: 3 },
            format: { with: /\A[A-Z]{3}\z/, message: "must be ISO 4217 code" },
            if: -> { currency.present? }

  validate :trial_ends_at_in_future, if: -> { status == "trial" && trial_ends_at.present? }

  # ============================================
  # CALLBACKS
  # ============================================

  before_validation :generate_slug, if: -> { slug.blank? }
  before_validation :normalize_domain
  before_validation :set_trial_end_date, if: -> { status == "trial" && trial_ends_at.blank? }
  after_create :set_plan_limits

  # ============================================
  # SCOPES
  # ============================================

  scope :active, -> { where(status: "active") }
  scope :trial, -> { where(status: "trial") }
  scope :suspended, -> { where(status: "suspended") }
  scope :cancelled, -> { where(status: "cancelled") }

  scope :trial_ending_soon, ->(days = 7) {
    where(status: "trial")
      .where("trial_ends_at <= ?", days.days.from_now)
      .where("trial_ends_at >= ?", Time.current)
  }

  scope :trial_expired, -> {
    where(status: "trial")
      .where("trial_ends_at < ?", Time.current)
  }

  scope :by_plan, ->(plan) { where(plan: plan) }
  scope :by_name, -> { order(:name) }

  scope :search_by_name, ->(query) {
    where("LOWER(name) LIKE :query OR LOWER(slug) LIKE :query OR LOWER(domain) LIKE :query",
          query: "%#{query.downcase}%")
  }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Estado del tenant
  def active?
    status == "active" && !deleted?
  end

  def trial?
    status == "trial"
  end

  def suspended?
    status == "suspended"
  end

  def cancelled?
    status == "cancelled"
  end

  # Trial
  def trial_expired?
    trial? && trial_ends_at.present? && trial_ends_at < Date.current
  end

  def trial_days_remaining
    return 0 unless trial? && trial_ends_at.present?

    [ (trial_ends_at - Date.current).to_i, 0 ].max
  end

  # Activación y suspensión
  def activate!
    update!(
      status: "active",
      subscription_starts_at: Date.current
    )
  end

  def suspend!(reason: nil)
    update!(
      status: "suspended",
      metadata: metadata.merge(suspension_reason: reason, suspended_at: Time.current)
    )
  end

  def unsuspend!
    update!(status: "active")
  end

  def cancel!
    update!(
      status: "cancelled",
      subscription_ends_at: Date.current
    )
  end

  # Límites del plan
  def within_user_limit?
    active_users.count < max_users
  end

  def user_limit_reached?
    !within_user_limit?
  end

  def remaining_user_slots
    [ max_users - active_users.count, 0 ].max
  end

  # Configuración
  def setting(key)
    settings.dig(key.to_s)
  end

  def set_setting(key, value)
    update!(settings: settings.merge(key.to_s => value))
  end

  # Display
  def display_name
    name
  end

  def to_s
    name
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Estadísticas generales
    def stats
      {
        total: count,
        active: active.count,
        trial: trial.count,
        suspended: suspended.count,
        cancelled: cancelled.count,
        trial_ending_soon: trial_ending_soon.count,
        trial_expired: trial_expired.count
      }
    end

    # Encontrar por slug o ID
    def find_by_slug_or_id(identifier)
      find_by(slug: identifier) || find_by(id: identifier)
    end
  end

  private

  # ============================================
  # PRIVATE METHODS
  # ============================================

  # Generar slug desde el nombre
  def generate_slug
    return if name.blank?

    base_slug = name.parameterize
    generated_slug = base_slug
    counter = 1

    while Tenant.exists?(slug: generated_slug)
      generated_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = generated_slug
  end

  # Normalizar dominio
  def normalize_domain
    self.domain = domain.downcase.strip if domain.present?
  end

  # Establecer fecha de fin de trial (30 días por defecto)
  def set_trial_end_date
    self.trial_ends_at = 30.days.from_now.to_date
  end

  # Validación custom: trial_ends_at debe ser futura
  def trial_ends_at_in_future
    if trial_ends_at < Date.current
      errors.add(:trial_ends_at, "must be in the future")
    end
  end

  # Establecer límites según el plan
  def set_plan_limits
    limits = PLAN_LIMITS[plan] || PLAN_LIMITS["trial"]
    update_columns(
      max_users: limits[:max_users],
      max_storage_gb: limits[:max_storage_gb]
    )
  end
end
