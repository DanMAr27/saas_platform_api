# app/models/user_node_scope.rb
# Scope de acceso a nodos organizacionales

class UserNodeScope < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable
  include SoftDeletable

  # ============================================
  # ENUMS
  # ============================================
  ACCESS_TYPES = %w[read write admin].freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :user
  belongs_to :organizational_node
  belongs_to :tenant
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :user_id, presence: true
  validates :organizational_node_id, presence: true,
            uniqueness: {
              scope: [ :user_id, :tenant_id ],
              conditions: -> { where(deleted_at: nil) }
            }
  validates :access_type, inclusion: { in: ACCESS_TYPES }

  # ============================================
  # SCOPES
  # ============================================
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_node, ->(node_id) { where(organizational_node_id: node_id) }
  scope :read_access, -> { where(access_type: "read") }
  scope :write_access, -> { where(access_type: "write") }
  scope :admin_access, -> { where(access_type: "admin") }
  scope :with_children, -> { where(include_children: true) }

  # ============================================
  # INSTANCE METHODS
  # ============================================
  def read_only?
    access_type == "read"
  end

  def can_write?
    access_type.in?(%w[write admin])
  end

  def can_admin?
    access_type == "admin"
  end

  # Obtener todos los nodos accesibles (incluyendo hijos si aplica)
  def accessible_nodes
    if include_children?
      organizational_node.descendants.active
    else
      OrganizationalNode.where(id: organizational_node_id)
    end
  end
end
