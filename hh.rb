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

# app/api/entities/organizational_node_entity.rb
# Entity para serializar nodos organizacionales en la API

module V1
  module Entities
    class OrganizationalNodeEntity < Grape::Entity
      # ============================================
      # CAMPOS BÁSICOS
      # ============================================
      expose :id
      expose :name
      expose :code
      expose :description, if: ->(obj, opts) { opts[:show_details] }
      expose :status

      # ============================================
      # 🆕 NUEVO: PATH COMPLETO
      # ============================================
      # Estos campos son clave para tu caso de uso de dropdowns

      # Path formateado: "CarfastCliente / Sucursal 1 / Departamento1"
      expose :full_path, if: ->(obj, opts) { opts[:include_path] } do |node|
        node.full_path
      end

      # Array de nombres: ["CarfastCliente", "Sucursal 1", "Departamento1"]
      expose :path_array, if: ->(obj, opts) { opts[:include_path] } do |node|
        node.path_array
      end

      # Array de IDs: [1, 5, 12] - útil para reconstruir la selección
      expose :path_ids, if: ->(obj, opts) { opts[:include_path] } do |node|
        node.path_ids
      end

      # ============================================
      # RELACIONES JERÁRQUICAS
      # ============================================
      expose :parent_id
      expose :level_id

      # Profundidad en el árbol (0 = raíz)
      expose :depth, if: ->(obj, opts) { opts[:show_hierarchy] } do |node|
        node.depth
      end

      # ============================================
      # NIVEL ORGANIZACIONAL
      # ============================================
      expose :level, if: ->(obj, opts) { opts[:include_level] }, using: OrganizationalNodeLevelEntity

      # ============================================
      # 🆕 NUEVO: INFORMACIÓN DEL PADRE
      # ============================================
      expose :parent, if: ->(obj, opts) { opts[:show_hierarchy] && obj.parent.present? } do |node|
        {
          id: node.parent.id,
          name: node.parent.name,
          level_name: node.parent.level.name
        }
      end

      # ============================================
      # 🆕 NUEVO: CAPACIDADES DEL NODO
      # ============================================
      # Indica si este nodo puede tener vehículos/usuarios asignados
      expose :can_assign_vehicles do |node|
        node.level&.allows_vehicles || false
      end

      expose :can_assign_users do |node|
        node.level&.allows_users || false
      end

      # ============================================
      # ESTADO DEL NODO
      # ============================================
      expose :is_root do |node|
        node.root?
      end

      expose :is_leaf do |node|
        node.leaf?
      end

      # ============================================
      # CONTADORES
      # ============================================
      expose :children_count, if: ->(obj, opts) { opts[:show_details] } do |node|
        node.children.count
      end

      expose :descendants_count, if: ->(obj, opts) { opts[:show_details] } do |node|
        node.descendants.count
      end

      # ============================================
      # UBICACIÓN FÍSICA
      # ============================================
      expose :address, if: ->(obj, opts) { opts[:show_details] }
      expose :city, if: ->(obj, opts) { opts[:show_details] }
      expose :state, if: ->(obj, opts) { opts[:show_details] }
      expose :postal_code, if: ->(obj, opts) { opts[:show_details] }
      expose :country, if: ->(obj, opts) { opts[:show_details] }

      # ============================================
      # CONTACTO
      # ============================================
      expose :phone, if: ->(obj, opts) { opts[:show_details] }
      expose :email, if: ->(obj, opts) { opts[:show_details] }

      # ============================================
      # VISTA DE ÁRBOL
      # ============================================
      # Los hijos se incluyen recursivamente cuando tree_view=true
      expose :children, if: ->(obj, opts) { opts[:tree_view] } do |node, opts|
        OrganizationalNodeEntity.represent(
          node.children.active.includes(:level),
          opts.merge(tree_view: true, include_level: true)
        )
      end

      # ============================================
      # TIMESTAMPS
      # ============================================
      expose :created_at, if: ->(obj, opts) { opts[:show_timestamps] }
      expose :updated_at, if: ->(obj, opts) { opts[:show_timestamps] }
    end
  end
end

# app/api/v1/entities/organizational_node_level_entity.rb

module V1
  module Entities
    class OrganizationalNodeLevelEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :name, documentation: { type: "String" }
      expose :slug, documentation: { type: "String" }
      expose :description, documentation: { type: "String" }
      expose :level_order, documentation: { type: "Integer" }
      expose :allows_vehicles, documentation: { type: "Boolean" }
      expose :allows_users, documentation: { type: "Boolean" }
      expose :is_system, documentation: { type: "Boolean" }

      with_options(if: ->(level, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end

# app/api/v1/tenant/organizational_nodes_api.rb
# API REST para gestión de nodos organizacionales
# Separada de organizational_levels_api para mejor organización

module V1
  module Tenant
    class OrganizationalNodesApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :organizational_nodes do
          # ============================================
          # LISTAR NODOS
          # ============================================
          desc "List organizational nodes",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Returns organizational structure. Can be flat list or tree."
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (required for platform admins)"
            optional :status, type: String, values: OrganizationalNode::STATUSES
            optional :level_id, type: Integer, desc: "Filter by level"
            optional :parent_id, type: Integer, desc: "Filter by parent node"
            optional :country, type: String, desc: "Filter by country code"
            optional :city, type: String, desc: "Filter by city"
            optional :search, type: String, desc: "Search by name, code, or city"
            optional :tree, type: Boolean, default: false, desc: "Return as tree structure"

            # 🆕 NUEVO: Filtros adicionales
            optional :allows_vehicles, type: Boolean, desc: "Filter nodes that allow vehicles"
            optional :allows_users, type: Boolean, desc: "Filter nodes that allow users"
            optional :only_roots, type: Boolean, desc: "Return only root nodes"
            optional :only_leaves, type: Boolean, desc: "Return only leaf nodes"

            optional :sort, type: String, values: %w[name code city recent path], desc: "Sort order"
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25, values: 1..100
          end
          get do
            authenticate!

            target_tenant = if current_user.platform_admin? && platform_context?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.includes(:level, :parent),
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            query = OrganizationalNodesQuery.new(
              nodes,
              params: declared(params),
              user: current_user
            )

            # ✏️ MEJORADO: Ahora usa tree_with_paths
            if params[:tree]
              tree_data = query.tree_with_paths(params[:parent_id])
              success_response(
                data: tree_data,
                meta: {
                  total_nodes: nodes.count,
                  root_nodes: nodes.roots.count
                }
              )
            else
              nodes = query.call.page(params[:page]).per(params[:per_page])

              success_response(
                data: nodes.map { |n|
                  Entities::OrganizationalNodeEntity.represent(
                    n,
                    show_details: true,
                    show_hierarchy: true,
                    include_level: true,
                    include_path: true  # 🆕 NUEVO: Incluir paths en listado
                  )
                },
                meta: {
                  current_page: nodes.current_page,
                  total_pages: nodes.total_pages,
                  total_count: nodes.total_count,
                  per_page: params[:per_page]
                }
              )
            end
          end

          # ============================================
          # 🆕 NUEVO: OPCIONES PARA DROPDOWN
          # ============================================
          # Este es el endpoint clave para tu caso de uso
          # GET /api/v1/tenant/organizational_nodes/dropdown/options
          desc "Get dropdown options with full paths",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Returns all active nodes with formatted paths for dropdowns/selects. Perfect for vehicle assignment."
          params do
            optional :tenant_id, type: Integer
            optional :only_vehicles, type: Boolean, default: false, desc: "Only nodes that allow vehicles"
            optional :grouped, type: Boolean, default: false, desc: "Group by root node"
          end
          get "dropdown/options" do
            authenticate!

            target_tenant = if current_user.platform_admin? && platform_context?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.active,
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            query = OrganizationalNodesQuery.new(nodes, params: declared(params))

            options = if params[:grouped]
              query.grouped_dropdown_options(only_vehicles: params[:only_vehicles])
            else
              query.dropdown_options(only_vehicles: params[:only_vehicles])
            end

            success_response(
              data: options,
              meta: {
                total_options: options.is_a?(Array) ? options.count : options.sum { |g| g[:options].count },
                grouped: params[:grouped]
              }
            )
          end

          # ============================================
          # 🆕 NUEVO: PATH COMPLETO DE UN NODO
          # ============================================
          # GET /api/v1/tenant/organizational_nodes/:id/path
          desc "Get full path of a specific node",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Returns the complete hierarchical path of a node"
          params do
            requires :id, type: Integer, desc: "Node ID"
          end
          get ":id/path" do
            authenticate!

            node = OrganizationalNode.find(params[:id])

            unless current_user.platform_admin? ||
                   (current_tenant && node.tenant_id == current_tenant.id)
              api_error(message: "Node not found or access denied", status: 404)
            end

            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            query = OrganizationalNodesQuery.new(OrganizationalNode.where(id: node.id))
            path_data = query.node_path(node.id)

            success_response(data: path_data)
          end

          # ============================================
          # 🆕 NUEVO: VALIDAR PATH
          # ============================================
          # POST /api/v1/tenant/organizational_nodes/validate_path
          desc "Validate a hierarchical path",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Validates that a sequence of node IDs forms a valid hierarchical path"
          params do
            requires :path_ids, type: Array[Integer], desc: "Array of node IDs from root to leaf"
          end
          post "validate_path" do
            authenticate!
            require_tenant!

            nodes = ActsAsTenant.with_tenant(current_tenant) do
              OrganizationalNode.all
            end

            query = OrganizationalNodesQuery.new(nodes)
            result = query.validate_path(params[:path_ids])

            if result[:valid]
              success_response(
                data: {
                  valid: true,
                  path: result[:nodes].map { |n|
                    {
                      id: n.id,
                      name: n.name,
                      level: n.level.name
                    }
                  }
                }
              )
            else
              api_error(message: result[:error], status: 422)
            end
          end

          # ============================================
          # VER NODO
          # ============================================
          desc "Get organizational node details",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer, desc: "Node ID"
          end
          get ":id" do
            authenticate!

            node = OrganizationalNode.find(params[:id])

            unless current_user.platform_admin? ||
                   (current_tenant && node.tenant_id == current_tenant.id)
              api_error(message: "Node not found or access denied", status: 404)
            end

            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            present node,
                    with: Entities::OrganizationalNodeEntity,
                    show_details: true,
                    show_hierarchy: true,
                    include_level: true,
                    include_path: true,  # 🆕 NUEVO
                    show_timestamps: true
          end

          # ============================================
          # CREAR NODO
          # ============================================
          desc "Create organizational node",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 201 }
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            requires :name, type: String, desc: "Node name"
            requires :level_id, type: Integer, desc: "Level ID"
            optional :parent_id, type: Integer, desc: "Parent node ID"
            optional :code, type: String, desc: "Unique code"
            optional :description, type: String
            optional :address, type: String
            optional :city, type: String
            optional :state, type: String
            optional :postal_code, type: String
            optional :country, type: String, desc: "ISO 2-letter country code"
            optional :phone, type: String
            optional :email, type: String
            optional :status, type: String, values: OrganizationalNode::STATUSES, default: "active"
          end
          post do
            authenticate!

            target_tenant = if current_user.platform_admin?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            temp_node = OrganizationalNode.new(tenant: target_tenant)
            authorize!(temp_node, :create?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::CreateService.call(
              params: declared(params).except(:tenant_id),
              tenant: target_tenant,
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::OrganizationalNodeEntity.represent(
                  result.data,
                  show_details: true,
                  include_level: true,
                  include_path: true  # 🆕 NUEVO
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ACTUALIZAR NODO
          # ============================================
          desc "Update organizational node",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :name, type: String
            optional :code, type: String
            optional :description, type: String
            optional :address, type: String
            optional :city, type: String
            optional :state, type: String
            optional :postal_code, type: String
            optional :country, type: String
            optional :phone, type: String
            optional :email, type: String
            optional :status, type: String, values: OrganizationalNode::STATUSES
          end
          patch ":id" do
            authenticate!

            node = OrganizationalNode.find(params[:id])
            authorize!(node, :update?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::UpdateService.call(
              node: node,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::OrganizationalNodeEntity.represent(
                  result.data,
                  show_details: true,
                  include_path: true  # 🆕 NUEVO
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # MOVER NODO
          # ============================================
          desc "Move node to different parent",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Changes the parent of a node, maintaining hierarchy integrity"
          params do
            requires :id, type: Integer, desc: "Node ID to move"
            requires :parent_id, type: Integer, desc: "New parent ID (null for root)", allow_blank: true
          end
          patch ":id/move" do
            authenticate!

            node = OrganizationalNode.find(params[:id])
            authorize!(node, :move?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::MoveService.call(
              node: node,
              new_parent_id: params[:parent_id],
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::OrganizationalNodeEntity.represent(
                  result.data,
                  show_details: true,
                  show_hierarchy: true,
                  include_path: true  # 🆕 NUEVO
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ELIMINAR NODO
          # ============================================
          desc "Delete organizational node",
                tags: [ "Tenant - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Soft deletes a node. Cannot delete nodes with children."
          params do
            requires :id, type: Integer
          end
          delete ":id" do
            authenticate!

            node = OrganizationalNode.find(params[:id])
            authorize!(node, :destroy?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::DestroyService.call(
              node: node,
              current_user: current_user
            )

            if result.success?
              success_response(message: result.message)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # OBTENER ANCESTROS
          # ============================================
          desc "Get node ancestors",
                tags: [ "Tenant - Organizational Nodes" ],
                detail: "Returns all parent nodes up to root"
          params do
            requires :id, type: Integer
          end
          get ":id/ancestors" do
            authenticate!

            node = OrganizationalNode.find(params[:id])
            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            ancestors = node.ancestor_chain

            success_response(
              data: ancestors.map { |n|
                Entities::OrganizationalNodeEntity.represent(n, include_level: true)
              }
            )
          end

          # ============================================
          # OBTENER DESCENDIENTES
          # ============================================
          desc "Get node descendants",
                tags: [ "Tenant - Organizational Nodes" ],
                detail: "Returns all child nodes recursively"
          params do
            requires :id, type: Integer
          end
          get ":id/descendants" do
            authenticate!

            node = OrganizationalNode.find(params[:id])
            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            descendants = node.descendant_tree

            success_response(
              data: descendants.map { |n|
                Entities::OrganizationalNodeEntity.represent(n, include_level: true)
              }
            )
          end

          # ============================================
          # 🆕 NUEVO: BREADCRUMBS
          # ============================================
          # GET /api/v1/tenant/organizational_nodes/:id/breadcrumbs
          desc "Get breadcrumb trail for a node",
                tags: [ "Tenant - Organizational Nodes" ],
                detail: "Returns the path from root to the specified node"
          params do
            requires :id, type: Integer
          end
          get ":id/breadcrumbs" do
            authenticate!

            node = OrganizationalNode.find(params[:id])
            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            query = OrganizationalNodesQuery.new(OrganizationalNode.where(tenant_id: node.tenant_id))
            breadcrumbs = query.breadcrumbs(node.id)

            success_response(data: breadcrumbs)
          end

          # ============================================
          # ESTADÍSTICAS
          # ============================================
          desc "Get organizational structure statistics",
                tags: [ "Tenant - Organizational Nodes" ]
          params do
            optional :tenant_id, type: Integer
          end
          get "stats/overview" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              require_tenant!
              current_tenant
            end

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              OrganizationalNode.includes(:level)
            end

            query = OrganizationalNodesQuery.new(nodes)

            success_response(data: query.stats)
          end
        end
      end
    end
  end
end
# app/models/organizational_node_closure.rb
# Tabla de closure para queries jerárquicas eficientes

class OrganizationalNodeClosure < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :ancestor, class_name: "OrganizationalNode"
  belongs_to :descendant, class_name: "OrganizationalNode"

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :ancestor_id, presence: true
  validates :descendant_id, presence: true
  validates :depth, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # ============================================
  # SCOPES
  # ============================================
  scope :direct_children, -> { where(depth: 1) }
  scope :self_references, -> { where("ancestor_id = descendant_id") }
  scope :excluding_self, -> { where("ancestor_id != descendant_id") }

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Reconstruir toda la closure table (útil para migraciones)
    def rebuild!
      transaction do
        delete_all

        OrganizationalNode.find_each do |node|
          # Self-reference
          create!(ancestor_id: node.id, descendant_id: node.id, depth: 0)

          # Ancestros
          node.parent&.ancestor_closures&.each do |closure|
            create!(
              ancestor_id: closure.ancestor_id,
              descendant_id: node.id,
              depth: closure.depth + 1
            )
          end
        end
      end
    end

    # Verificar integridad
    def verify_integrity
      errors = []

      # Verificar que todos los nodos tienen self-reference
      OrganizationalNode.find_each do |node|
        unless exists?(ancestor_id: node.id, descendant_id: node.id, depth: 0)
          errors << "Missing self-reference for node #{node.id}"
        end
      end

      errors
    end
  end
end
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
class ServiceResult
  attr_reader :success, :data, :errors, :message, :meta

  def initialize(success:, data: nil, errors: nil, message: nil, meta: nil)
    @success = success
    @data = data
    @errors = errors || []
    @message = message
    @meta = meta || {}
  end

  # Métodos de conveniencia para crear resultados

  def self.success(data: nil, message: nil, meta: nil)
    new(
      success: true,
      data: data,
      message: message,
      meta: meta
    )
  end

  def self.failure(errors: nil, message: nil, data: nil, meta: nil)
    # Normalizar errores a array
    normalized_errors = case errors
    when String
                          [ errors ]
    when Hash
                          errors.values.flatten
    when Array
                          errors
    when ActiveModel::Errors
                          errors.full_messages
    else
                          [ "Unknown error occurred" ]
    end

    new(
      success: false,
      errors: normalized_errors,
      message: message || normalized_errors.first,
      data: data,
      meta: meta
    )
  end

  # Predicados

  def success?
    @success == true
  end

  def failure?
    !success?
  end

  def has_data?
    @data.present?
  end

  def has_errors?
    @errors.present?
  end

  # Conversión a hash (útil para APIs)

  def to_h
    hash = {
      success: @success
    }

    hash[:data] = @data if @data.present?
    hash[:message] = @message if @message.present?
    hash[:errors] = @errors if @errors.present?
    hash[:meta] = @meta if @meta.present?

    hash
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  # Acceso a datos con métodos delegation

  def method_missing(method_name, *args, &block)
    if @data.respond_to?(method_name)
      @data.public_send(method_name, *args, &block)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    @data.respond_to?(method_name) || super
  end

  # Operadores útiles

  # Permite encadenar operaciones
  # result = service1.call.then { |data| service2.call(data) }
  def then
    if success? && block_given?
      yield(@data)
    else
      self
    end
  end

  # Rescue de errores automático
  # result = service.call.rescue_from(ActiveRecord::RecordNotFound) { |e| ... }
  def rescue_from(exception_class, &block)
    self
  rescue exception_class => e
    block.call(e) if block_given?
    ServiceResult.failure(errors: e.message)
  end

  # Helpers para debugging

  def inspect
    "#<ServiceResult success: #{@success}, data: #{@data.inspect}, errors: #{@errors.inspect}>"
  end
end
# Módulo para incluir en servicios base
module ServiceResultHelper
  # Crear resultado de éxito
  def success(data: nil, message: nil, meta: nil)
    ServiceResult.success(data: data, message: message, meta: meta)
  end

  # Crear resultado de fallo
  def failure(errors: nil, message: nil, data: nil, meta: nil)
    ServiceResult.failure(errors: errors, message: message, data: data, meta: meta)
  end

  # Ejecutar bloque y retornar ServiceResult automáticamente
  def result_from
    yield
  rescue ActiveRecord::RecordInvalid => e
    failure(errors: e.record.errors.full_messages)
  rescue ActiveRecord::RecordNotFound => e
    failure(errors: "Record not found", message: e.message)
  rescue StandardError => e
    Rails.logger.error("[ServiceError] #{e.class.name}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    failure(errors: "An error occurred", message: e.message)
  end
end
# app/services/tenant/organizational_nodes/create_service.rb

module Tenants
  module OrganizationalNodes
    class CreateService
      include ServiceResultHelper

      attr_reader :params, :tenant, :current_user

      def initialize(params:, tenant:, current_user:)
        @params = params
        @tenant = tenant
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        validation_result = validate_params
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          node = create_node
          return failure(errors: node.errors.full_messages) unless node.persisted?

          set_paper_trail_context

          success(data: node, message: "Organizational node created successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[CreateOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to create organizational node")
      end

      private

      def validate_params
        required_fields = %i[name level_id]
        missing_fields = required_fields.select { |f| params[f].blank? }

        if missing_fields.any?
          return failure(errors: "Missing required fields: #{missing_fields.join(', ')}")
        end

        # Validar nivel
        level = OrganizationalNodeLevel.find_by(id: params[:level_id], tenant_id: tenant.id)
        unless level
          return failure(errors: "Level not found or doesn't belong to tenant")
        end

        # Validar padre si se proporciona
        if params[:parent_id]
          parent = OrganizationalNode.find_by(id: params[:parent_id], tenant_id: tenant.id)
          unless parent
            return failure(errors: "Parent node not found or doesn't belong to tenant")
          end

          # Validar que el nivel del padre sea superior
          if parent.level.level_order >= level.level_order
            return failure(errors: "Parent node must be of a higher level")
          end
        end

        success(data: { valid: true })
      end

      def create_node
        node_params = {
          tenant: tenant,
          level_id: params[:level_id],
          parent_id: params[:parent_id],
          name: params[:name],
          code: params[:code],
          description: params[:description],
          address: params[:address],
          city: params[:city],
          state: params[:state],
          postal_code: params[:postal_code],
          country: params[:country],
          phone: params[:phone],
          email: params[:email],
          status: params[:status] || "active",
          metadata: params[:metadata] || {},
          created_by: current_user&.id
        }

        OrganizationalNode.create!(node_params.compact)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: { performed_action: "create_organizational_node" }
        }
      end
    end
  end
end

# db/migrate/XXXXXX_create_user_node_scopes.rb
# Scopes de acceso a nodos organizacionales para usuarios

class CreateUserNodeScopes < ActiveRecord::Migration[8.0]
  def change
    create_table :user_node_scopes do |t|
      # Relación usuario-nodo
      t.bigint :user_id, null: false
      t.bigint :organizational_node_id, null: false
      t.bigint :tenant_id, null: false

      # Tipo de acceso
      t.string :access_type, limit: 20, default: "read", null: false # read, write, admin

      # ¿Incluye nodos hijos?
      t.boolean :include_children, default: true, null: false

      # Auditoría
      t.bigint :created_by
      t.datetime :deleted_at
      t.bigint :deleted_by

      t.timestamps
    end

    # Índices
    add_index :user_node_scopes, :user_id
    add_index :user_node_scopes, :organizational_node_id
    add_index :user_node_scopes, :tenant_id
    add_index :user_node_scopes, [ :user_id, :organizational_node_id, :tenant_id ],
              unique: true,
              name: "index_user_node_scopes_unique",
              where: "deleted_at IS NULL"
    add_index :user_node_scopes, :deleted_at

    # Foreign keys
    add_foreign_key :user_node_scopes, :users, on_delete: :cascade
    add_foreign_key :user_node_scopes, :organizational_nodes, on_delete: :cascade
    add_foreign_key :user_node_scopes, :tenants, on_delete: :cascade
    add_foreign_key :user_node_scopes, :users, column: :created_by, on_delete: :nullify
  end
end

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

# app/services/tenant/scopes/assign_vehicle_scope_service.rb

module Tenants
  module Scopes
    class AssignVehicleScopeService
      include ServiceResultHelper

      attr_reader :user, :vehicle, :tenant, :params, :current_user

      def initialize(user:, vehicle:, tenant:, params:, current_user:)
        @user = user
        @vehicle = vehicle
        @tenant = tenant
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validaciones
        unless user.has_tenant_access?(tenant.id)
          return failure(errors: "User doesn't have access to this tenant")
        end

        unless vehicle.tenant_id == tenant.id
          return failure(errors: "Vehicle doesn't belong to this tenant")
        end

        ActiveRecord::Base.transaction do
          scope = create_or_update_scope
          return failure(errors: scope.errors.full_messages) unless scope.persisted?

          set_paper_trail_context

          success(data: scope, message: "Vehicle scope assigned successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[AssignVehicleScopeService] Error: #{e.message}")
        failure(errors: "Failed to assign vehicle scope")
      end

      private

      def create_or_update_scope
        scope = UserVehicleScope.find_or_initialize_by(
          user: user,
          vehicle: vehicle,
          tenant: tenant
        )

        scope.assign_attributes(
          access_type: params[:access_type] || "read",
          valid_from: params[:valid_from],
          valid_until: params[:valid_until],
          created_by: current_user&.id
        )

        scope.save!
        scope
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end

# app/services/tenant/scopes/assign_node_scope_service.rb

module Tenants
  module Scopes
    class AssignNodeScopeService
      include ServiceResultHelper

      attr_reader :user, :node, :tenant, :params, :current_user

      def initialize(user:, node:, tenant:, params:, current_user:)
        @user = user
        @node = node
        @tenant = tenant
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que el usuario pertenezca al tenant
        unless user.has_tenant_access?(tenant.id)
          return failure(errors: "User doesn't have access to this tenant")
        end

        # Validar que el nodo pertenezca al tenant
        unless node.tenant_id == tenant.id
          return failure(errors: "Node doesn't belong to this tenant")
        end

        ActiveRecord::Base.transaction do
          scope = create_or_update_scope
          return failure(errors: scope.errors.full_messages) unless scope.persisted?

          set_paper_trail_context

          success(data: scope, message: "Node scope assigned successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[AssignNodeScopeService] Error: #{e.message}")
        failure(errors: "Failed to assign node scope")
      end

      private

      def create_or_update_scope
        scope = UserNodeScope.find_or_initialize_by(
          user: user,
          organizational_node: node,
          tenant: tenant
        )

        scope.assign_attributes(
          access_type: params[:access_type] || "read",
          include_children: params[:include_children].nil? ? true : params[:include_children],
          created_by: current_user&.id
        )

        scope.save!
        scope
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end





{
  "success": true,
  "data": [
    {
      "id": 3,
      "name": "Global Logistics Pro Central",
      "code": "CENTRAL",
      "description": null,
      "parent_id": null,
      "level_id": 5,
      "depth": 0,
      "level": {
        "id": 3,
        "name": "Global Logistics Pro Central",
        "order": null,
        "allows_vehicles": null,
        "allows_users": null
      },
      "status": "active",
      "is_active": true,
      "is_root": true,
      "is_leaf": false,
      "can_have_children": true,
      "can_assign_vehicles": false,
      "can_assign_users": true,
      "metadata": {},
      "counters": {
        "children_count": null,
        "descendants_count": null,
        "vehicles_count": null
      },
      "full_path": "Global Logistics Pro Central",
      "created_at": "2025-12-01T10:32:02+01:00",
      "updated_at": "2025-12-01T10:32:02+01:00",
      "created_by": null,
      "has_children": true,
      "is_expanded": false,
      "children": [
        {
          "id": 4,
          "name": "Northern Region",
          "code": "REGION-N",
          "description": null,
          "parent_id": 3,
          "level_id": 6,
          "depth": 1,
          "level": {
            "id": 4,
            "name": "Northern Region",
            "order": null,
            "allows_vehicles": null,
            "allows_users": null
          },
          "status": "active",
          "is_active": true,
          "is_root": false,
          "is_leaf": false,
          "can_have_children": true,
          "can_assign_vehicles": false,
          "can_assign_users": true,
          "metadata": {},
          "counters": {
            "children_count": null,
            "descendants_count": null,
            "vehicles_count": null
          },
          "full_path": "Global Logistics Pro Central / Northern Region",
          "created_at": "2025-12-01T10:32:02+01:00",
          "updated_at": "2025-12-01T10:32:02+01:00",
          "created_by": null,
          "has_children": true,
          "is_expanded": false,
          "children": [
            {
              "id": 5,
              "name": "Barcelona Hub",
              "code": "BCN-01",
              "description": null,
              "parent_id": 4,
              "level_id": 7,
              "depth": 2,
              "level": {
                "id": 5,
                "name": "Barcelona Hub",
                "order": null,
                "allows_vehicles": null,
                "allows_users": null
              },
              "status": "active",
              "is_active": true,
              "is_root": false,
              "is_leaf": false,
              "can_have_children": true,
              "can_assign_vehicles": true,
              "can_assign_users": true,
              "location": {
                "address": null,
                "city": null,
                "state": null,
                "postal_code": null,
                "country": null,
                "full_address": null
              },
              "metadata": {},
              "counters": {
                "children_count": null,
                "descendants_count": null,
                "vehicles_count": null
              },
              "full_path": "Global Logistics Pro Central / Northern Region / Barcelona Hub",
              "created_at": "2025-12-01T10:32:03+01:00",
              "updated_at": "2025-12-01T10:32:03+01:00",
              "created_by": null,
              "has_children": true,
              "is_expanded": false,
              "children": [
                {
                  "id": 6,
                  "name": "Sales Department",
                  "code": "BCN-SALES",
                  "description": null,
                  "parent_id": 5,
                  "level_id": 8,
                  "depth": 3,
                  "level": {
                    "id": 6,
                    "name": "Sales Department",
                    "order": null,
                    "allows_vehicles": null,
                    "allows_users": null
                  },
                  "status": "active",
                  "is_active": true,
                  "is_root": false,
                  "is_leaf": true,
                  "can_have_children": true,
                  "can_assign_vehicles": false,
                  "can_assign_users": true,
                  "metadata": {},
                  "counters": {
                    "children_count": null,
                    "descendants_count": null,
                    "vehicles_count": null
                  },
                  "full_path": "Global Logistics Pro Central / Northern Region / Barcelona Hub / Sales Department",
                  "created_at": "2025-12-01T10:32:04+01:00",
                  "updated_at": "2025-12-01T10:32:04+01:00",
                  "created_by": null,
                  "has_children": false,
                  "is_expanded": false,
                  "children": []
                }
              ]
            }
          ]
        }
      ]
    }
  ],
  "meta": {
    "tenant_id": 3,
    "tenant_name": "Global Logistics Pro",
    "total_nodes": 4,
    "root_nodes": 1,
    "leaf_nodes": 0,
    "active_nodes": 4,
    "generated_at": "2025-12-02T11:04:31+01:00",
    "cache_enabled": false
  },
  "timestamp": "2025-12-02T11:04:31+01:00"
}
