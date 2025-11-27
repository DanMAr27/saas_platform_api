# app/models/organizational_node_level.rb

class OrganizationalNodeLevel < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable
  include SoftDeletable
  include Tenantable

  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :tenant
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  has_many :organizational_nodes, foreign_key: :level_id, dependent: :restrict_with_error

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true,
            uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } },
            format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase, numbers and underscores" }
  validates :level_order, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # ============================================
  # CALLBACKS
  # ============================================
  before_validation :generate_slug, if: -> { slug.blank? }

  # ============================================
  # SCOPES
  # ============================================
  scope :by_order, -> { order(:level_order, :name) }
  scope :system_levels, -> { where(is_system: true) }
  scope :custom_levels, -> { where(is_system: false) }
  scope :allows_vehicles, -> { where(allows_vehicles: true) }
  scope :allows_users, -> { where(allows_users: true) }

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Crear niveles base del sistema
    def create_default_levels_for_tenant(tenant)
      [
        { name: "Company", slug: "company", level_order: 1, is_system: true },
        { name: "Region", slug: "region", level_order: 2, is_system: true },
        { name: "Branch", slug: "branch", level_order: 3, is_system: true },
        { name: "Department", slug: "department", level_order: 4, is_system: true }
      ].each do |level_attrs|
        find_or_create_by!(tenant: tenant, slug: level_attrs[:slug]) do |level|
          level.name = level_attrs[:name]
          level.level_order = level_attrs[:level_order]
          level.is_system = level_attrs[:is_system]
          level.allows_vehicles = true
          level.allows_users = true
        end
      end
    end
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================

  def display_name
    "#{name} (Level #{level_order})"
  end

  def to_s
    name
  end

  # Verificar si hay nodos en este nivel
  def has_nodes?
    organizational_nodes.exists?
  end

  # Obtener el siguiente nivel inferior
  def next_level
    self.class.where(tenant_id: tenant_id)
              .where("level_order > ?", level_order)
              .order(:level_order)
              .first
  end

  # Obtener el nivel superior
  def previous_level
    self.class.where(tenant_id: tenant_id)
              .where("level_order < ?", level_order)
              .order(level_order: :desc)
              .first
  end

  private

  def generate_slug
    return if name.blank?
    self.slug = name.parameterize.underscore
  end
end
