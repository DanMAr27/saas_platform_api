# app/queries/organizational_nodes_scope_query.rb
# Query object especializado para gestión de scopes de usuarios
# Este es el cerebro del sistema de selección de nodos

class OrganizationalNodesScopeQuery
  attr_reader :relation, :user, :params

  def initialize(relation = OrganizationalNode.all, user: nil, params: {})
    @relation = relation
    @user = user
    @params = params
  end

  # ============================================
  # MÉTODO PRINCIPAL: ÁRBOL CON INFORMACIÓN DE SELECCIÓN
  # ============================================
  # Este método construye el árbol completo decorado con información
  # sobre qué nodos están seleccionados para un usuario específico
  def selection_tree
    # Paso 1: Obtener los IDs que están físicamente guardados en BD
    stored_ids = fetch_stored_scope_ids

    # Paso 2: Expandir esos IDs a todos los nodos que cubren (stored + descendientes)
    effective_ids = expand_to_effective_ids(stored_ids)

    # Paso 3: Calcular qué nodos deben mostrarse expandidos en la UI
    expanded_ids = calculate_expanded_node_ids(stored_ids)

    # Paso 4: Construir el árbol completo con toda esta información
    roots = fetch_root_nodes
    tree = build_selection_tree_structure(roots, stored_ids, effective_ids)

    # Paso 5: Retornar árbol + metadata para que el frontend sepa qué hacer
    {
      tree: tree,
      metadata: {
        user_id: user&.id,
        # IDs guardados en BD (los mínimos necesarios)
        stored_ids: stored_ids,
        # IDs efectivos (stored + todos sus descendientes)
        effective_ids: effective_ids,
        # IDs que deben mostrarse expandidos en la UI
        expanded_ids: expanded_ids,
        # Estadísticas útiles
        total_coverage: effective_ids.count,
        stored_count: stored_ids.count,
        # Ratio de optimización (cuánto espacio ahorramos)
        optimization_ratio: calculate_optimization_ratio(stored_ids, effective_ids)
      }
    }
  end

  # ============================================
  # EXPANDIR IDS A EFECTIVOS (stored → effective)
  # ============================================
  # Toma los IDs guardados en BD y retorna todos los nodos que cubren
  # Ejemplo: Si guardamos [2], pero 2 tiene hijos [3,4,5,6,7,8,9]
  # Retorna: [2,3,4,5,6,7,8,9]
  def expand_to_effective_ids(stored_ids)
    return [] if stored_ids.empty?

    # Usar closure table para obtener todos los descendientes eficientemente
    # Esta query es MUY eficiente porque la closure table ya tiene precalculadas
    # todas las relaciones ancestro-descendiente
    descendant_ids = OrganizationalNodeClosure
      .where(ancestor_id: stored_ids)
      .pluck(:descendant_id)
      .uniq

    # Los effective_ids son: stored + descendientes
    # Usamos Set para eliminar duplicados automáticamente
    Set.new(stored_ids + descendant_ids).to_a
  end

  # ============================================
  # CALCULAR NODOS A EXPANDIR EN UI
  # ============================================
  # Calcula qué nodos deben mostrarse expandidos para que el usuario
  # vea automáticamente los nodos seleccionados sin tener que navegar
  # Ejemplo: Si seleccionamos nodo 8, necesitamos expandir: [1, 2, 5, 8]
  # (toda la ruta desde la raíz hasta el nodo seleccionado)
  def calculate_expanded_node_ids(stored_ids)
    return [] if stored_ids.empty?

    # Para cada nodo guardado, obtener toda su cadena de ancestros
    ancestor_ids = OrganizationalNodeClosure
      .where(descendant_id: stored_ids)
      .where.not(depth: 0) # Excluir self-reference
      .pluck(:ancestor_id)
      .uniq

    # Los nodos a expandir son: ancestros + stored
    # Así mostramos toda la ruta desde raíz hasta los seleccionados
    Set.new(ancestor_ids + stored_ids).to_a
  end

  # ============================================
  # OPTIMIZAR SELECCIÓN (effective → stored)
  # ============================================
  # Este es el algoritmo inverso: toma una lista de IDs seleccionados
  # y retorna solo los IDs mínimos necesarios para guardar
  # Ejemplo: Si usuario selecciona [2,3,4,5,6,7,8,9] y 2 es padre de todos
  # Retorna: [2] (porque 2 cubre a todos sus descendientes)
  def optimize_selection(selected_ids)
    return [] if selected_ids.empty?

    # Cargar todos los nodos seleccionados con su información de jerarquía
    nodes = @relation.where(id: selected_ids)
                     .includes(:parent, :children)
                     .index_by(&:id)

    optimized = []
    processed = Set.new

    # Procesar cada nodo seleccionado
    selected_ids.each do |node_id|
      next if processed.include?(node_id)

      node = nodes[node_id]
      next unless node

      # Si el nodo tiene padre y el padre también está seleccionado
      if node.parent_id && selected_ids.include?(node.parent_id)
        parent = nodes[node.parent_id]

        # Verificar si TODOS los hermanos también están seleccionados
        sibling_ids = parent.children.pluck(:id)
        all_siblings_selected = sibling_ids.all? { |id| selected_ids.include?(id) }

        if all_siblings_selected
          # Si todos los hijos están seleccionados, solo guardar el padre
          # Marcar todos los hermanos como procesados
          sibling_ids.each { |id| processed.add(id) }
          # El padre se agregará cuando lo procesemos
          next
        end
      end

      # Si llegamos aquí, este nodo debe guardarse
      optimized << node_id
      processed.add(node_id)

      # Marcar todos sus descendientes como procesados
      # (están cubiertos por este nodo)
      descendant_ids = OrganizationalNodeClosure
        .where(ancestor_id: node_id)
        .where.not(depth: 0)
        .pluck(:descendant_id)
      descendant_ids.each { |id| processed.add(id) }
    end

    optimized.sort
  end

  # ============================================
  # VALIDAR PATH DE NODOS
  # ============================================
  # Valida que una secuencia de IDs forme un path jerárquico válido
  # Útil cuando el frontend envía una selección y queremos verificarla
  def validate_node_path(path_ids)
    return { valid: false, error: "Empty path" } if path_ids.blank?

    # Cargar todos los nodos
    nodes = @relation.where(id: path_ids).includes(:level, :parent).index_by(&:id)
    ordered_nodes = path_ids.map { |id| nodes[id] }.compact

    # Verificar que encontramos todos
    if ordered_nodes.size != path_ids.size
      missing = path_ids - ordered_nodes.map(&:id)
      return {
        valid: false,
        error: "Nodes not found: #{missing.join(', ')}"
      }
    end

    # Verificar jerarquía correcta
    ordered_nodes.each_with_index do |node, index|
      if index > 0
        # Cada nodo debe ser hijo directo del anterior
        expected_parent_id = ordered_nodes[index - 1].id
        unless node.parent_id == expected_parent_id
          return {
            valid: false,
            error: "Invalid hierarchy: #{node.name} is not child of #{ordered_nodes[index - 1].name}"
          }
        end
      elsif node.parent_id.present?
        # El primer nodo debe ser raíz
        return { valid: false, error: "First node must be root" }
      end
    end

    {
      valid: true,
      path: ordered_nodes.map { |n| { id: n.id, name: n.name, level: n.level.name } }
    }
  end

  # ============================================
  # OBTENER OPCIONES PARA DROPDOWN
  # ============================================
  # Genera una lista plana de opciones para usar en <select> o dropdowns
  def dropdown_options(only_vehicles: false)
    scope = @relation.active.includes(:level, ancestors: :level)
    scope = scope.joins(:level).where(organizational_node_levels: { allows_vehicles: true }) if only_vehicles

    nodes = scope.to_a

    # Construir opciones con información completa
    options = nodes.map do |node|
      {
        value: node.id,
        label: node.full_path, # "Company / Region / Branch"
        level_order: node.level.level_order,
        level_name: node.level.name,
        parent_id: node.parent_id,
        depth: node.depth,
        can_assign_vehicles: node.level.allows_vehicles,
        can_assign_users: node.level.allows_users,
        is_leaf: node.leaf?
      }
    end

    # Ordenar por path para mejor UX
    options.sort_by { |opt| opt[:label] }
  end

  # ============================================
  # OBTENER SCOPE EFECTIVO DE UN USUARIO
  # ============================================
  # Retorna todos los IDs de nodos a los que el usuario tiene acceso
  # Este método se usa en las policies para validar acceso
  def user_effective_scope_ids
    return [] unless user

    # Usar caché para no calcular esto en cada request
    Rails.cache.fetch("user:#{user.id}:effective_scope_ids", expires_in: 1.hour) do
      stored_ids = fetch_stored_scope_ids
      expand_to_effective_ids(stored_ids)
    end
  end

  # ============================================
  # MÉTODOS PRIVADOS
  # ============================================
  private

  # Obtener IDs almacenados en BD para el usuario
  def fetch_stored_scope_ids
    return [] unless user

    UserNodeScope.where(user_id: user.id)
                 .pluck(:organizational_node_id)
  end

  # Obtener nodos raíz con eager loading
  def fetch_root_nodes
    @relation.roots
             .active
             .includes(:level, :created_by_user, children: [ :level, :children ])
             .joins(:level)
             .order("organizational_node_levels.level_order, organizational_nodes.name")
  end

  # Construir árbol con información de selección
  def build_selection_tree_structure(nodes, stored_ids, effective_ids)
    nodes.map do |node|
      build_selection_node(node, stored_ids, effective_ids)
    end
  end

  # Construir datos de un nodo individual con selection_state
  def build_selection_node(node, stored_ids, effective_ids)
    # Calcular estado de selección
    is_stored = stored_ids.include?(node.id)
    is_effective = effective_ids.include?(node.id)

    # Un nodo está "heredado" si está en effective pero no en stored
    # Significa que está cubierto por un ancestro
    is_inherited = is_effective && !is_stored

    # Un nodo está "parcial" si tiene hijos y solo algunos están seleccionados
    is_partial = has_partial_selection?(node, effective_ids)

    # Encontrar qué ancestro cubre este nodo (si está heredado)
    covering_parent_id = find_covering_parent(node, stored_ids)

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

      # Path completo para mostrar en UI
      full_path: node.full_path,

      # ⭐ ESTADO DE SELECCIÓN (lo más importante para el frontend)
      selection_state: {
        # ¿Este nodo está guardado directamente en BD?
        is_selected: is_stored,

        # ¿Está cubierto por un padre seleccionado?
        is_inherited: is_inherited,

        # ¿Tiene algunos hijos seleccionados pero no todos?
        is_partial: is_partial,

        # ¿Está en el scope efectivo del usuario?
        effective_coverage: is_effective,

        # ¿Está físicamente guardado en BD?
        stored_directly: is_stored,

        # ID del padre que cubre este nodo (si aplica)
        parent_coverage_id: covering_parent_id,

        # Nombre del padre que cubre (para mostrar en UI)
        covered_by_name: covering_parent_id ? find_node_name(covering_parent_id) : nil
      },

      # Capacidades
      can_assign_vehicles: node.level.allows_vehicles,
      can_assign_users: node.level.allows_users,

      # Estado
      status: node.status,
      is_active: node.status == "active",
      is_root: node.root?,
      is_leaf: node.leaf?,

      # Contadores útiles para la UI
      counters: {
        direct_children: node.children.count,
        total_descendants: node.descendants.count,
        vehicles_count: node.vehicles.count,
        # Cuántos descendientes están en el scope
        selected_descendants: count_selected_descendants(node, effective_ids)
      },

      # Hijos recursivos con su propio selection_state
      children: build_selection_children(node, stored_ids, effective_ids),

      # Flags de UI
      has_children: node.children.any?
    }
  end

  # Construir hijos con información de selección
  def build_selection_children(node, stored_ids, effective_ids)
    children = node.children.active
                   .includes(:level, :children, :created_by_user)
                   .joins(:level)
                   .order("organizational_node_levels.level_order, organizational_nodes.name")

    children.map do |child|
      build_selection_node(child, stored_ids, effective_ids)
    end
  end

  # Verificar si un nodo tiene selección parcial
  # (algunos hijos seleccionados pero no todos)
  def has_partial_selection?(node, effective_ids)
    return false if node.leaf?

    children_ids = node.children.pluck(:id)
    return false if children_ids.empty?

    # Contar cuántos hijos están en el scope
    selected_count = children_ids.count { |id| effective_ids.include?(id) }

    # Es parcial si hay al menos uno seleccionado pero no todos
    selected_count > 0 && selected_count < children_ids.count
  end

  # Encontrar el ancestro más cercano que cubre este nodo
  def find_covering_parent(node, stored_ids)
    return nil if node.root?

    # Obtener ancestros ordenados del más cercano al más lejano
    ancestor_ids = OrganizationalNodeClosure
      .where(descendant_id: node.id)
      .where.not(depth: 0) # Excluir self-reference
      .order(depth: :asc) # Del más cercano al más lejano
      .pluck(:ancestor_id)

    # Encontrar el primer ancestro que está en stored_ids
    ancestor_ids.find { |id| stored_ids.include?(id) }
  end

  # Contar descendientes seleccionados
  def count_selected_descendants(node, effective_ids)
    return 0 if node.leaf?

    descendant_ids = OrganizationalNodeClosure
      .where(ancestor_id: node.id)
      .where.not(depth: 0)
      .pluck(:descendant_id)

    descendant_ids.count { |id| effective_ids.include?(id) }
  end

  # Encontrar nombre de un nodo por ID
  def find_node_name(node_id)
    @relation.find_by(id: node_id)&.name
  end

  # Calcular ratio de optimización
  def calculate_optimization_ratio(stored_ids, effective_ids)
    return 0 if effective_ids.empty?

    saved_records = effective_ids.count - stored_ids.count
    percentage = (saved_records.to_f / effective_ids.count * 100).round(1)

    {
      stored_count: stored_ids.count,
      effective_count: effective_ids.count,
      saved_records: saved_records,
      percentage: percentage
    }
  end
end
