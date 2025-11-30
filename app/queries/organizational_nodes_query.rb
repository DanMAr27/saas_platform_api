# app/queries/organizational_nodes_query.rb
# Query object para filtrar y buscar nodos organizacionales

class OrganizationalNodesQuery
  attr_reader :relation, :params, :user

  def initialize(relation = OrganizationalNode.all, params: {}, user: nil)
    @relation = relation.extending(Scopes)
    @params = params
    @user = user
  end

  def call
    @relation = apply_filters(@relation)
    @relation = apply_search(@relation)
    @relation = apply_sorting(@relation)
    @relation
  end

  # Obtener árbol jerárquico completo (método existente)
  def tree(parent_id = nil)
    nodes = if parent_id
      @relation.where(parent_id: parent_id)
    else
      @relation.roots
    end

    nodes = nodes.includes(:level, children: [ :level, :children ])
    build_tree_with_paths(nodes)
  end

  # 🆕 NUEVO: Obtener árbol con paths completos calculados
  # Este método construye recursivamente el árbol con los paths completos
  def tree_with_paths(parent_id = nil)
    if parent_id
      node = @relation.find(parent_id)
      [ build_tree_node_with_path(node) ]
    else
      roots = @relation.roots.includes(:level, :children)
      roots.map { |node| build_tree_node_with_path(node) }
    end
  end

  # 🆕 NUEVO: Opciones para dropdown
  # Retorna array de opciones formateadas para usar en <select>
  # Ejemplo de uso: GET /api/v1/tenant/organizational_nodes/dropdown/options
  def dropdown_options(only_vehicles: false)
    scope = call.active.includes(:level, ancestors: :level)
    scope = scope.allows_vehicles if only_vehicles

    # Obtener todos los nodos y construir opciones
    nodes = scope.to_a

    options = nodes.map do |node|
      {
        value: node.id,
        label: node.full_path,
        level_order: node.level.level_order,
        level_name: node.level.name,
        parent_id: node.parent_id,
        root_name: node.root_node&.name,
        can_assign_vehicles: node.level.allows_vehicles,
        can_assign_users: node.level.allows_users,
        path_ids: node.path_ids
      }
    end

    # Ordenar por path completo para mejor UX
    options.sort_by { |opt| opt[:label] }
  end

  # 🆕 NUEVO: Opciones agrupadas por nodo raíz
  # Útil para <optgroup> en HTML o grupos en componentes
  def grouped_dropdown_options(only_vehicles: false)
    options = dropdown_options(only_vehicles: only_vehicles)

    grouped = options.group_by { |opt| opt[:root_name] }

    grouped.map do |root_name, items|
      {
        group: root_name || "Root Nodes",
        options: items
      }
    end
  end

  # 🆕 NUEVO: Path completo de un nodo específico
  # Útil para mostrar el path seleccionado o validar
  def node_path(node_id)
    node = @relation.find(node_id)
    {
      id: node.id,
      path: node.full_path,
      path_array: node.path_array,
      path_ids: node.path_ids,
      level: {
        id: node.level.id,
        name: node.level.name,
        order: node.level.level_order
      }
    }
  end

  # Obtener ruta de breadcrumbs de un nodo (método existente mejorado)
  def breadcrumbs(node_id)
    node = @relation.find(node_id)
    ancestors = node.ancestor_chain.to_a

    (ancestors + [ node ]).map do |n|
      {
        id: n.id,
        name: n.name,
        level_name: n.level.name
      }
    end
  end

  # Estadísticas de la estructura (método existente mejorado)
  def stats
    {
      total_nodes: @relation.count,
      root_nodes: @relation.roots.count,
      leaf_nodes: @relation.leaves.count,
      active_nodes: @relation.active.count,
      inactive_nodes: @relation.inactive.count,
      by_level: @relation.joins(:level)
                        .group("organizational_node_levels.name")
                        .count,
      by_status: @relation.group(:status).count,
      nodes_with_vehicles: @relation.allows_vehicles.count
    }
  end

  # 🆕 NUEVO: Validar que un path de IDs sea válido
  # Útil cuando el frontend envía una selección de path
  def validate_path(path_ids)
    return { valid: false, error: "Empty path" } if path_ids.blank?

    nodes = @relation.where(id: path_ids).includes(:level, :parent).index_by(&:id)
    ordered_nodes = path_ids.map { |id| nodes[id] }.compact

    return { valid: false, error: "Some nodes not found" } if ordered_nodes.size != path_ids.size

    # Verificar que el path sea jerárquicamente correcto
    ordered_nodes.each_with_index do |node, index|
      if index > 0
        expected_parent_id = ordered_nodes[index - 1].id
        unless node.parent_id == expected_parent_id
          return {
            valid: false,
            error: "Invalid hierarchy: #{node.name} is not child of #{ordered_nodes[index - 1].name}"
          }
        end
      elsif node.parent_id.present?
        return { valid: false, error: "First node must be root" }
      end
    end

    { valid: true, nodes: ordered_nodes }
  end

  private

  # Aplicar filtros (método existente mejorado)
  def apply_filters(relation)
    relation = relation.where(status: params[:status]) if params[:status]
    relation = relation.where(level_id: params[:level_id]) if params[:level_id]

    if params[:parent_id] && !params[:tree]
      relation = relation.where(parent_id: params[:parent_id])
    end

    relation = relation.where(country: params[:country]) if params[:country]
    relation = relation.where(city: params[:city]) if params[:city]

    # 🆕 NUEVO: Filtros adicionales
    relation = relation.allows_vehicles if params[:allows_vehicles]
    relation = relation.allows_users if params[:allows_users]
    relation = relation.roots if params[:only_roots]
    relation = relation.leaves if params[:only_leaves]

    relation
  end

  def apply_search(relation)
    return relation unless params[:search].present?

    search_term = "%#{params[:search].downcase}%"
    relation.where(
      "LOWER(name) LIKE :term OR LOWER(code) LIKE :term OR LOWER(city) LIKE :term",
      term: search_term
    )
  end

  # Aplicar ordenación (método existente mejorado)
  def apply_sorting(relation)
    case params[:sort]
    when "name"
      relation.order(name: :asc)
    when "code"
      relation.order(code: :asc)
    when "city"
      relation.order(city: :asc, name: :asc)
    when "recent"
      relation.order(created_at: :desc)
    when "path"
      # Ordenar por path completo (por nivel y nombre)
      relation.joins(:level).order("organizational_node_levels.level_order, organizational_nodes.name")
    else
      relation.joins(:level).order("organizational_node_levels.level_order, organizational_nodes.name")
    end
  end

  # 🆕 NUEVO: Construir árbol con paths completos
  def build_tree_with_paths(nodes, parent_path = "")
    nodes.map do |node|
      current_path = parent_path.blank? ? node.name : "#{parent_path} / #{node.name}"

      {
        id: node.id,
        name: node.name,
        code: node.code,
        full_path: current_path,
        level: {
          id: node.level_id,
          name: node.level.name,
          order: node.level.level_order
        },
        parent_id: node.parent_id,
        status: node.status,
        allows_vehicles: node.level.allows_vehicles,
        allows_users: node.level.allows_users,
        has_children: !node.leaf?,
        children: build_tree_with_paths(
          node.children.active.includes(:level),
          current_path
        )
      }
    end
  end

  # 🆕 NUEVO: Construir nodo con path recursivo
  # Este es el método clave para construir el árbol con paths
  def build_tree_node_with_path(node, parent_path = "")
    current_path = parent_path.blank? ? node.name : "#{parent_path} / #{node.name}"

    children_data = node.children.active.includes(:level, :children).map do |child|
      build_tree_node_with_path(child, current_path)
    end

    {
      id: node.id,
      name: node.name,
      code: node.code,
      full_path: current_path,
      level: {
        id: node.level_id,
        name: node.level.name,
        order: node.level.level_order
      },
      parent_id: node.parent_id,
      status: node.status,
      depth: node.depth,
      allows_vehicles: node.level.allows_vehicles,
      allows_users: node.level.allows_users,
      has_children: children_data.any?,
      children: children_data
    }
  end

  module Scopes
    def accessible_by_user(user)
      # TODO: Implementar cuando se agreguen user_node_scopes en Fase 6
      all
    end
  end
end
