# app/models/organizational_node.rb
# Nodo de la estructura organizacional (sucursal, división, departamento)

class OrganizationalNode < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable
  include SoftDeletable
  include Tenantable

  # ============================================
  # ENUMS
  # ============================================
  STATUSES = %w[active inactive].freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :tenant
  belongs_to :level, class_name: "OrganizationalNodeLevel", foreign_key: :level_id
  belongs_to :parent, class_name: "OrganizationalNode", optional: true
  belongs_to :created_by_user, class_name: "User", foreign_key: :created_by, optional: true

  has_many :children, class_name: "OrganizationalNode",
           foreign_key: :parent_id,
           dependent: :restrict_with_error

  # Closure table associations
  has_many :ancestor_closures, class_name: "OrganizationalNodeClosure",
           foreign_key: :descendant_id,
           dependent: :destroy
  has_many :descendant_closures, class_name: "OrganizationalNodeClosure",
           foreign_key: :ancestor_id,
           dependent: :destroy

  has_many :ancestors, through: :ancestor_closures, source: :ancestor
  has_many :descendants, through: :descendant_closures, source: :descendant

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :name, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: STATUSES }
  validates :code, uniqueness: { scope: :tenant_id, allow_nil: true, conditions: -> { where(deleted_at: nil) } }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validate :parent_must_be_higher_level
  validate :parent_must_be_same_tenant
  validate :prevent_circular_reference

  # ============================================
  # CALLBACKS
  # ============================================
  after_create :create_closure_records
  after_update :update_closure_records, if: :saved_change_to_parent_id?
  before_destroy :check_if_has_children

  # ============================================
  # SCOPES
  # ============================================
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :roots, -> { where(parent_id: nil) }
  scope :by_level, ->(level_id) { where(level_id: level_id) }
  scope :by_name, -> { order(:name) }
  scope :with_level, -> { includes(:level) }
  scope :leaves, -> { where.not(id: select(:parent_id).distinct) }

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Obtener árbol completo
    def tree(parent = nil)
      nodes = parent ? parent.children : roots
      nodes.active.includes(:level, :children).order(:name)
    end

    # Buscar por ruta completa (ej: "Company/Region/Branch")
    def find_by_path(path, tenant:)
      names = path.split("/")
      current_node = nil

      names.each do |name|
        query = where(tenant: tenant, name: name.strip)
        query = query.where(parent: current_node)
        current_node = query.first
        return nil unless current_node
      end

      current_node
    end
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Verificar si es nodo raíz
  def root?
    parent_id.nil?
  end

  # Verificar si tiene hijos
  def leaf?
    children.none?
  end

  # Verificar si es ancestro de otro nodo
  def ancestor_of?(other_node)
    other_node.ancestors.include?(self)
  end

  # Verificar si es descendiente de otro nodo
  def descendant_of?(other_node)
    ancestors.include?(other_node)
  end

  # Obtener todos los ancestros ordenados (padres, abuelos, etc.)
  def ancestor_chain
    ancestors.joins(:level)
             .where.not(id: id)
             .order("organizational_node_levels.level_order")
  end

  # Obtener todos los descendientes ordenados (hijos, nietos, etc.)
  def descendant_tree
    descendants.joins(:level)
               .where.not(id: id)
               .order("organizational_node_levels.level_order")
  end

  # Obtener hijos directos activos
  def direct_children
    children.active.includes(:level).order(:name)
  end

  # Obtener profundidad del nodo (0 = raíz, 1 = hijo directo de raíz, etc.)
  def depth
    return 0 if root?
    ancestor_closures.where.not(ancestor_id: id).maximum(:depth) || 0
  end

  # Ruta completa del nodo (ej: "Company > Region > Branch")
  def full_path(separator: " > ")
    ancestor_chain.pluck(:name).push(name).join(separator)
  end

  # Ruta completa con códigos (ej: "COMP/REG-N/BCN-01")
  def code_path(separator: "/")
    path_nodes = ancestor_chain.to_a + [ self ]
    path_nodes.map { |n| n.code || n.name }.join(separator)
  end

  # Obtener raíz del árbol
  def root_node
    return self if root?
    ancestors.roots.first
  end

  # Obtener todos los hermanos (nodos con el mismo padre)
  def siblings
    if parent_id
      parent.children.where.not(id: id)
    else
      self.class.roots.where(tenant_id: tenant_id).where.not(id: id)
    end
  end

  # Mover nodo a otro padre
  def move_to(new_parent)
    return false if new_parent && new_parent.descendant_of?(self)

    update(parent: new_parent)
  end

  # Display
  def display_name
    "#{name} (#{level.name})"
  end

  def to_s
    name
  end

  # Información de ubicación
  def location_summary
    parts = [ address, city, state, postal_code, country ].compact
    parts.join(", ")
  end

  # Estadísticas
  def stats
    {
      depth: depth,
      children_count: children.count,
      descendants_count: descendants.count,
      is_root: root?,
      is_leaf: leaf?
    }
  end

  private

  # Validar que el padre sea de nivel superior
  def parent_must_be_higher_level
    return unless parent_id.present? && level_id.present?
    return unless parent.present?

    if parent.level.level_order >= level.level_order
      errors.add(:parent_id, "must be of a higher level")
    end
  end

  # Validar mismo tenant
  def parent_must_be_same_tenant
    return unless parent_id.present?
    return unless parent.present?

    if parent.tenant_id != tenant_id
      errors.add(:parent_id, "must belong to the same tenant")
    end
  end

  # Prevenir referencia circular
  def prevent_circular_reference
    return unless parent_id.present?

    if parent_id == id
      errors.add(:parent_id, "cannot be itself")
    elsif parent&.ancestor_of?(self)
      errors.add(:parent_id, "would create a circular reference")
    end
  end

  # Crear registros en closure table
  def create_closure_records
    # Self-reference
    OrganizationalNodeClosure.create!(
      ancestor_id: id,
      descendant_id: id,
      depth: 0
    )

    # Copiar todos los ancestros del padre
    if parent_id.present?
      parent.ancestor_closures.each do |closure|
        OrganizationalNodeClosure.create!(
          ancestor_id: closure.ancestor_id,
          descendant_id: id,
          depth: closure.depth + 1
        )
      end
    end
  end

  # Actualizar closure table cuando cambia el padre
  def update_closure_records
    # Eliminar closures antiguos (excepto self-reference)
    OrganizationalNodeClosure.where(descendant_id: id)
                             .where.not(ancestor_id: id)
                             .delete_all

    # Recrear closures para el nuevo padre
    if parent_id.present?
      parent.ancestor_closures.each do |closure|
        OrganizationalNodeClosure.create!(
          ancestor_id: closure.ancestor_id,
          descendant_id: id,
          depth: closure.depth + 1
        )
      end
    end

    # Actualizar descendientes
    update_descendant_closures
  end

  # Actualizar closures de descendientes
  def update_descendant_closures
    descendants.each do |descendant|
      descendant.send(:update_closure_records)
    end
  end

  # Prevenir eliminación si tiene hijos
  def check_if_has_children
    if children.exists?
      errors.add(:base, "Cannot delete node with children")
      throw :abort
    end
  end
end
