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
