# app/models/vehicle.rb
# Vehículo de la flota

class Vehicle < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable
  include SoftDeletable
  include Tenantable

  # ============================================
  # ENUMS
  # ============================================
  STATUSES = %w[active inactive maintenance].freeze
  VEHICLE_TYPES = %w[car truck van motorcycle bus trailer].freeze
  FUEL_TYPES = %w[gasoline diesel electric hybrid].freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :tenant
  belongs_to :organizational_node, optional: true
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  has_many :user_vehicle_scopes, dependent: :destroy
  has_many :scoped_users, through: :user_vehicle_scopes, source: :user

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :name, presence: true, length: { maximum: 255 }
  validates :license_plate, presence: true,
            uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :fleet_number, uniqueness: { scope: :tenant_id, allow_nil: true }
  validates :status, inclusion: { in: STATUSES }
  validates :vehicle_type, inclusion: { in: VEHICLE_TYPES }, allow_nil: true
  validates :fuel_type, inclusion: { in: FUEL_TYPES }, allow_nil: true

  # ============================================
  # CALLBACKS
  # ============================================
  before_validation :normalize_license_plate

  # ============================================
  # SCOPES
  # ============================================
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :in_maintenance, -> { where(status: "maintenance") }
  scope :by_type, ->(type) { where(vehicle_type: type) }
  scope :by_node, ->(node_id) { where(organizational_node_id: node_id) }
  scope :by_name, -> { order(:name) }
  scope :expiring_registration, ->(days = 30) {
    where("registration_expires_at BETWEEN ? AND ?", Date.current, days.days.from_now)
  }
  scope :expiring_insurance, ->(days = 30) {
    where("insurance_expires_at BETWEEN ? AND ?", Date.current, days.days.from_now)
  }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Estado del vehículo
  def active?
    status == "active"
  end

  def in_maintenance?
    status == "maintenance"
  end

  # Expiración de documentos
  def registration_expired?
    registration_expires_at.present? && registration_expires_at < Date.current
  end

  def insurance_expired?
    insurance_expires_at.present? && insurance_expires_at < Date.current
  end

  def registration_expires_soon?(days = 30)
    return false unless registration_expires_at.present?
    registration_expires_at.between?(Date.current, days.days.from_now)
  end

  def insurance_expires_soon?(days = 30)
    return false unless insurance_expires_at.present?
    insurance_expires_at.between?(Date.current, days.days.from_now)
  end

  # Mantenimiento
  def requires_maintenance?
    last_maintenance_date.blank? || last_maintenance_date < 6.months.ago
  end

  # Acceso
  def accessible_by?(user)
    return true if user.platform_admin?
    return true if user.tenant_admin?(tenant_id)

    user_vehicle_scopes.exists?(user_id: user.id)
  end

  # Ubicación organizacional
  def organization_path
    return "Unassigned" unless organizational_node
    organizational_node.full_path
  end

  # Display
  def display_name
    "#{name} (#{license_plate})"
  end

  def to_s
    display_name
  end

  private

  def normalize_license_plate
    self.license_plate = license_plate&.upcase&.strip
  end
end
