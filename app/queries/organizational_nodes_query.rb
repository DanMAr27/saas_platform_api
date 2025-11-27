# app/queries/organizational_nodes_query.rb

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

  # Obtener árbol jerárquico completo
  def tree(parent_id = nil)
    nodes = if parent_id
      # Si hay parent_id específico, obtener desde ese nodo
      @relation.where(parent_id: parent_id)
    else
      # Si no, obtener las raíces
      @relation.roots
    end

    # Eager loading para evitar N+1 queries
    nodes = nodes.includes(:level, children: [ :level, :children ])

    # Retornar los nodos representados con la opción tree_view
    nodes.map do |node|
      Entities::OrganizationalNodeEntity.represent(
        node,
        tree_view: true,
        include_level: true
      )
    end
  end

  # ALTERNATIVA: Si prefieres el hash simple (sin entity)
  def tree_hash(parent_id = nil)
    nodes = call
    roots = parent_id ? nodes.where(parent_id: parent_id) : nodes.roots
    build_tree(roots.includes(:level, :children))
  end

  # Obtener ruta de breadcrumbs de un nodo
  def breadcrumbs(node_id)
    node = OrganizationalNode.find(node_id)
    node.ancestor_chain.to_a + [ node ]
  end

  # Estadísticas de la estructura
  def stats
    {
      total_nodes: relation.count,
      root_nodes: relation.roots.count,
      leaf_nodes: relation.leaves.count, # Usa scope si existe, si no: relation.select { |n| n.leaf? }.count
      max_depth: relation.maximum(:depth) || 0, # Asumiendo que tienes columna depth
      by_level: relation.group(:level_id).count,
      by_status: relation.group(:status).count
    }
  end

  private

  def apply_filters(relation)
    relation = relation.where(status: params[:status]) if params[:status]
    relation = relation.where(level_id: params[:level_id]) if params[:level_id]

    # Solo aplicar parent_id si no estamos pidiendo árbol
    # porque el árbol maneja esto internamente
    if params[:parent_id] && !params[:tree]
      relation = relation.where(parent_id: params[:parent_id])
    end

    # Filtrar por país
    relation = relation.where(country: params[:country]) if params[:country]

    # Filtrar por ciudad
    relation = relation.where(city: params[:city]) if params[:city]

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
    else
      # Por defecto ordenar por nivel y nombre
      relation.joins(:level).order("organizational_node_levels.level_order, organizational_nodes.name")
    end
  end

  def build_tree(nodes, depth = 0)
    nodes.map do |node|
      {
        id: node.id,
        name: node.name,
        code: node.code,
        level_id: node.level_id,
        level_name: node.level.name,
        parent_id: node.parent_id,
        status: node.status,
        depth: depth,
        has_children: !node.leaf?,
        children: build_tree(node.children.where(status: "active").includes(:level), depth + 1)
      }
    end
  end

  module Scopes
    # Para futuras extensiones con scopes de usuario
    def accessible_by_user(user)
      # TODO: Implementar cuando se agreguen user_node_scopes en Fase 6
      all
    end
  end
end
