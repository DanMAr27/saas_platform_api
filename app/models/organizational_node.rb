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

  # 🆕 NUEVO: Asociación con vehículos (ajusta según tu modelo)
  has_many :vehicles, dependent: :restrict_with_error

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

  # 🆕 NUEVO: Validar que el nivel permita vehículos si hay vehículos asignados
  validate :level_allows_vehicles, if: :has_vehicles?

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

  # 🆕 NUEVO: Scopes adicionales para filtrado
  scope :allows_vehicles, -> { joins(:level).where(organizational_node_levels: { allows_vehicles: true }) }
  scope :allows_users, -> { joins(:level).where(organizational_node_levels: { allows_users: true }) }
  scope :with_full_hierarchy, -> { includes(:level, :parent, :ancestors) }

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Obtener árbol completo
    def tree(parent = nil)
      nodes = parent ? parent.children : roots
      nodes.active.includes(:level, :children).order(:name)
    end

    # ✏️ MEJORADO: Ahora acepta separador personalizado
    def find_by_path(path, tenant:, separator: "/")
      names = path.split(separator)
      current_node = nil

      names.each do |name|
        query = where(tenant: tenant, name: name.strip)
        query = query.where(parent: current_node)
        current_node = query.first
        return nil unless current_node
      end

      current_node
    end

    # 🆕 NUEVO: Obtener todas las opciones formateadas para dropdown
    # Este método es clave para tu caso de uso de selects
    def dropdown_options(tenant:, only_vehicles: false)
      scope = where(tenant: tenant).active.with_full_hierarchy
      scope = scope.allows_vehicles if only_vehicles

      scope.map do |node|
        {
          value: node.id,
          label: node.full_path,                    # Path completo: "Cliente / Sucursal 1 / Dpto 1"
          level_order: node.level.level_order,
          level_name: node.level.name,
          parent_id: node.parent_id,
          root_name: node.root_node&.name,
          can_assign_vehicles: node.level.allows_vehicles,
          can_assign_users: node.level.allows_users
        }
      end.sort_by { |opt| opt[:label] }
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

  # ✏️ MEJORADO: Ruta completa del nodo usando el nuevo método auxiliar
  def full_path(separator: " / ")
    path_array.join(separator)
  end

  # 🆕 NUEVO: Array con los nombres del path
  # Ejemplo: ["CarfastCliente", "Sucursal 1", "Departamento1"]
  def path_array
    ancestor_chain.pluck(:name).push(name)
  end

  # 🆕 NUEVO: Array con los IDs del path (útil para reconstruir selección)
  # Ejemplo: [1, 5, 12]
  def path_ids
    ancestor_chain.pluck(:id).push(id)
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

  # 🆕 NUEVO: Información para dropdown/select
  # Devuelve un hash con toda la info necesaria para el frontend
  def to_dropdown_option
    {
      value: id,
      label: full_path,
      level_order: level.level_order,
      level_name: level.name,
      parent_id: parent_id,
      root_name: root_node&.name,
      can_assign_vehicles: level.allows_vehicles,
      can_assign_users: level.allows_users,
      path_ids: path_ids
    }
  end

  # 🆕 NUEVO: Información completa con jerarquía
  # Útil para respuestas API detalladas
  def hierarchy_info
    {
      id: id,
      name: name,
      code: code,
      full_path: full_path,
      path_array: path_array,
      level: {
        id: level.id,
        name: level.name,
        order: level.level_order
      },
      depth: depth,
      is_root: root?,
      is_leaf: leaf?,
      parent: parent ? { id: parent.id, name: parent.name } : nil,
      children_count: children.count
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

  # 🆕 NUEVO: Validar que el nivel permita vehículos
  def level_allows_vehicles
    unless level&.allows_vehicles
      errors.add(:base, "This organizational level does not allow vehicle assignment")
    end
  end

  # 🆕 NUEVO: Helper para validación
  def has_vehicles?
    vehicles.any?
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
