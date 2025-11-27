# app/models/user_vehicle_scope.rb
# Scope de acceso a vehículos específicos

class UserVehicleScope < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable
  include SoftDeletable

  # ============================================
  # ENUMS
  # ============================================
  ACCESS_TYPES = %w[read write drive].freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :user
  belongs_to :vehicle
  belongs_to :tenant
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :user_id, presence: true
  validates :vehicle_id, presence: true,
            uniqueness: {
              scope: [ :user_id, :tenant_id ],
              conditions: -> { where(deleted_at: nil) }
            }
  validates :access_type, inclusion: { in: ACCESS_TYPES }
  validate :valid_dates

  # ============================================
  # CALLBACKS
  # ============================================
  before_save :set_default_dates, if: :new_record?

  # ============================================
  # SCOPES
  # ============================================
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_vehicle, ->(vehicle_id) { where(vehicle_id: vehicle_id) }
  scope :read_access, -> { where(access_type: "read") }
  scope :write_access, -> { where(access_type: "write") }
  scope :drive_access, -> { where(access_type: "drive") }
  scope :active, -> {
    where("(valid_from IS NULL OR valid_from <= ?) AND (valid_until IS NULL OR valid_until >= ?)",
          Time.current, Time.current)
  }
  scope :expired, -> { where("valid_until < ?", Time.current) }

  # ============================================
  # INSTANCE METHODS
  # ============================================
  def read_only?
    access_type == "read"
  end

  def can_write?
    access_type.in?(%w[write drive])
  end

  def can_drive?
    access_type == "drive"
  end

  def active?
    (valid_from.nil? || valid_from <= Time.current) &&
    (valid_until.nil? || valid_until >= Time.current)
  end

  def expired?
    valid_until.present? && valid_until < Time.current
  end

  private

  def valid_dates
    return unless valid_from.present? && valid_until.present?

    if valid_from > valid_until
      errors.add(:valid_until, "must be after valid_from")
    end
  end

  def set_default_dates
    self.valid_from ||= Time.current
  end
end
