# app/queries/organizational_nodes_tree_query.rb
# Query object especializado para construir árboles organizacionales
# Separado de OrganizationalNodesQuery para mantener responsabilidades claras

class OrganizationalNodesTreeQuery
  attr_reader :relation, :params, :user

  def initialize(relation = OrganizationalNode.all, params: {}, user: nil)
    @relation = relation.extending(Scopes)
    @params = params
    @user = user
  end

  # Construir árbol completo para gestión/visualización
  # Este es el método principal para GET /tree
  def management_tree
    roots = fetch_root_nodes
    build_tree_structure(roots)
  end

  # Obtener un subárbol específico desde un nodo
  def subtree(parent_id)
    parent_node = @relation.find(parent_id)
    [ build_node_structure(parent_node) ]
  end

  # Construir árbol aplanado (útil para algunos casos)
  def flat_tree
    nodes = apply_filters(@relation)
    nodes = apply_search(nodes)
    nodes = apply_sorting(nodes)

    nodes.map { |node| build_node_data(node, include_children: false) }
  end

  # Obtener estadísticas del árbol
  def tree_stats
    {
      total_nodes: @relation.count,
      root_nodes: @relation.roots.count,
      leaf_nodes: @relation.leaves.count,
      max_depth: calculate_max_depth,
      active_nodes: @relation.active.count,
      inactive_nodes: @relation.inactive.count,
      nodes_by_level: nodes_by_level_stats,
      nodes_with_vehicles: @relation.joins(:level)
                                    .where(organizational_node_levels: { allows_vehicles: true })
                                    .count
    }
  end

  # Validar integridad del árbol
  def validate_tree_integrity
    errors = []

    # Verificar nodos huérfanos (padre inexistente)
    orphaned = @relation.where.not(parent_id: nil)
                        .where.not(parent_id: @relation.select(:id))
    errors << "Found #{orphaned.count} orphaned nodes" if orphaned.any?

    # Verificar referencias circulares
    @relation.find_each do |node|
      if has_circular_reference?(node)
        errors << "Circular reference detected at node #{node.id}"
      end
    end

    # Verificar niveles inconsistentes
    invalid_levels = @relation.joins(:parent, :level)
                              .where("organizational_nodes.level_id <= parents_organizational_nodes.level_id")
    errors << "Found #{invalid_levels.count} nodes with invalid level hierarchy" if invalid_levels.any?

    { valid: errors.empty?, errors: errors }
  end

  # Buscar nodo por path completo
  # Ejemplo: "OHL SERVICIOS / Fleet & Mobility / AMAC CS"
  def find_by_path(path_string, separator: " / ")
    names = path_string.split(separator).map(&:strip)
    current_node = nil

    names.each_with_index do |name, index|
      query = @relation.where(name: name)
      query = query.where(parent_id: current_node&.id)
      query = query.where(parent_id: nil) if index.zero? && current_node.nil?

      current_node = query.first
      return nil unless current_node
    end

    current_node
  end

  private

  # ============================================
  # CONSTRUCCIÓN DEL ÁRBOL
  # ============================================

  def fetch_root_nodes
    roots = @relation.roots
    roots = apply_filters(roots)
    roots = apply_search(roots)
    roots = apply_sorting(roots)

    # Cargar asociaciones necesarias de una vez
    roots.includes(:level, :created_by_user, children: [ :level, :children ])
  end

  def build_tree_structure(nodes)
    nodes.map { |node| build_node_structure(node) }
  end

  def build_node_structure(node)
    {
      # Identificación básica
      id: node.id,
      name: node.name,
      code: node.code,
      description: node.description,

      # Jerarquía
      parent_id: node.parent_id,
      level_id: node.level_id,
      depth: node.depth,

      # Información del nivel
      level: {
        id: node.level.id,
        name: node.level.name,
        order: node.level.level_order,
        allows_vehicles: node.level.allows_vehicles,
        allows_users: node.level.allows_users
      },

      # Estado
      status: node.status,
      is_active: node.status == "active",
      is_root: node.root?,
      is_leaf: node.leaf?,

      # Capacidades del nodo
      can_have_children: can_have_children?(node),
      can_assign_vehicles: node.level.allows_vehicles,
      can_assign_users: node.level.allows_users,

      # Ubicación
      location: build_location_data(node),

      # Contacto
      contact: build_contact_data(node),

      # Metadata
      metadata: node.metadata || {},

      # Contadores
      counters: {
        direct_children: node.children.count,
        total_descendants: node.descendants.count,
        vehicles_count: node.vehicles.count
      },

      # Path completo
      full_path: node.full_path,

      # Auditoría
      created_at: node.created_at,
      updated_at: node.updated_at,
      created_by: node.created_by_user&.email,

      # Hijos (recursivo)
      children: build_children_structure(node),

      # Flags de UI
      has_children: node.children.any?,
      is_expanded: false # Default, el frontend lo maneja
    }
  end

  def build_children_structure(node)
    # Solo incluir hijos activos para el árbol de gestión
    children = node.children.active.includes(:level, :children, :created_by_user)
    children = children.order("organizational_node_levels.level_order, organizational_nodes.name")
               .joins(:level)

    children.map { |child| build_node_structure(child) }
  end

  def build_node_data(node, include_children: true)
    data = {
      id: node.id,
      name: node.name,
      code: node.code,
      parent_id: node.parent_id,
      level_id: node.level_id,
      status: node.status,
      full_path: node.full_path,
      depth: node.depth,
      is_root: node.root?,
      is_leaf: node.leaf?
    }

    data[:children] = build_children_structure(node) if include_children
    data
  end

  # ============================================
  # HELPERS DE CONSTRUCCIÓN
  # ============================================

  def build_location_data(node)
    return nil unless node.address.present? || node.city.present?

    {
      address: node.address,
      city: node.city,
      state: node.state,
      postal_code: node.postal_code,
      country: node.country,
      full_address: node.location_summary
    }
  end

  def build_contact_data(node)
    return nil unless node.phone.present? || node.email.present?

    {
      phone: node.phone,
      email: node.email
    }
  end

  def can_have_children?(node)
    # Un nodo puede tener hijos si existe un nivel inferior al suyo
    node.level.next_level.present?
  end

  # ============================================
  # FILTROS Y BÚSQUEDA
  # ============================================

  def apply_filters(relation)
    relation = relation.where(status: params[:status]) if params[:status]
    relation = relation.where(level_id: params[:level_id]) if params[:level_id]
    relation = relation.where(country: params[:country]) if params[:country]
    relation = relation.where(city: params[:city]) if params[:city]

    # Filtros específicos
    relation = relation.joins(:level).where(organizational_node_levels: { allows_vehicles: true }) if params[:only_vehicle_nodes]
    relation = relation.joins(:level).where(organizational_node_levels: { allows_users: true }) if params[:only_user_nodes]

    relation
  end

  def apply_search(relation)
    return relation unless params[:search].present?

    search_term = "%#{params[:search].downcase}%"
    relation.where(
      "LOWER(organizational_nodes.name) LIKE :term OR
       LOWER(organizational_nodes.code) LIKE :term OR
       LOWER(organizational_nodes.city) LIKE :term",
      term: search_term
    )
  end

  def apply_sorting(relation)
    case params[:sort]
    when "name"
      relation.order(name: :asc)
    when "code"
      relation.order(code: :asc)
    when "recent"
      relation.order(created_at: :desc)
    else
      # Por defecto, ordenar por nivel y nombre
      relation.joins(:level).order("organizational_node_levels.level_order, organizational_nodes.name")
    end
  end

  # ============================================
  # ESTADÍSTICAS Y VALIDACIÓN
  # ============================================

  def calculate_max_depth
    @relation.maximum(:depth) || 0
  end

  def nodes_by_level_stats
    @relation.joins(:level)
             .group("organizational_node_levels.name", "organizational_node_levels.level_order")
             .order("organizational_node_levels.level_order")
             .count
             .transform_keys { |k| k.first }
  end

  def has_circular_reference?(node, visited_ids = [])
    return false if node.parent_id.nil?
    return true if visited_ids.include?(node.id)

    visited_ids << node.id
    parent = @relation.find_by(id: node.parent_id)
    return false unless parent

    has_circular_reference?(parent, visited_ids)
  end

  # ============================================
  # SCOPES MODULE
  # ============================================

  module Scopes
    def accessible_by_user(user)
      # TODO: Implementar filtrado por scopes de usuario
      # Por ahora retorna todos para administradores
      all
    end

    def with_stats
      select("organizational_nodes.*")
        .select("(SELECT COUNT(*) FROM organizational_nodes children WHERE children.parent_id = organizational_nodes.id) as children_count")
        .select("(SELECT COUNT(*) FROM vehicles WHERE vehicles.organizational_node_id = organizational_nodes.id) as vehicles_count")
    end
  end
end
