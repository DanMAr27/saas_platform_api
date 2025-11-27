# app/api/v1/tenant/organizational_nodes_api.rb

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
            optional :sort, type: String, values: %w[name code city recent], desc: "Sort order"
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25, values: 1..100
          end
          get do
            authenticate!

            # Determinar tenant según el contexto
            target_tenant = if current_user.platform_admin? && platform_context?
              # Platform admin DEBE proporcionar tenant_id
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              # Usuario con contexto tenant: usar su tenant del JWT
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Obtener nodos usando policy scope DENTRO del contexto del tenant
            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.includes(:level, :parent),
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            # Aplicar query
            query = OrganizationalNodesQuery.new(
              nodes,
              params: declared(params),
              user: current_user
            )

            # Si se pide como árbol
            if params[:tree]
              tree_data = query.tree(params[:parent_id])
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
                    include_level: true
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

            # Validar acceso
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

            # Determinar tenant
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

            # Autorizar
            temp_node = OrganizationalNode.new(tenant: target_tenant)
            authorize!(temp_node, :create?, policy_class: OrganizationalNodePolicy)

            result = ::Tenant::OrganizationalNodes::CreateService.call(
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
                  include_level: true
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

            result = ::Tenant::OrganizationalNodes::UpdateService.call(
              node: node,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::OrganizationalNodeEntity.represent(
                  result.data,
                  show_details: true
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

            result = ::Tenant::OrganizationalNodes::MoveService.call(
              node: node,
              new_parent_id: params[:parent_id],
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::OrganizationalNodeEntity.represent(
                  result.data,
                  show_details: true,
                  show_hierarchy: true
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

            result = ::Tenant::OrganizationalNodes::DestroyService.call(
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
          # ESTADÍSTICAS
          # ============================================
          desc "Get organizational structure statistics",
                tags: [ "Tenant - Organizational Nodes" ]
          params do
            optional :tenant_id, type: Integer
          end
          get "stats/overview" do
            authenticate!

            # Determinar tenant
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

        # ============================================
        # ENDPOINTS DE NIVELES
        # ============================================
        namespace :organizational_levels do
          desc "List organizational levels",
                tags: [ "Tenant - Organizational Nodes" ]
          params do
            optional :tenant_id, type: Integer
            optional :is_system, type: Boolean
            optional :allows_vehicles, type: Boolean
            optional :allows_users, type: Boolean
          end
          get do
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

            levels = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNodeLevel.all,
                policy_scope_class: OrganizationalNodeLevelPolicy::Scope
              )
            end

            query = OrganizationalNodeLevelsQuery.new(levels, params: declared(params))
            levels = query.call

            success_response(
              data: levels.map { |l|
                Entities::OrganizationalNodeLevelEntity.represent(l, show_timestamps: true)
              }
            )
          end

          desc "Create organizational level",
                tags: [ "Tenant - Organizational Nodes" ]
          params do
            optional :tenant_id, type: Integer
            requires :name, type: String
            optional :slug, type: String
            optional :description, type: String
            requires :level_order, type: Integer
            optional :allows_vehicles, type: Boolean, default: true
            optional :allows_users, type: Boolean, default: true
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

            # Solo admin puede crear niveles
            unless current_user.platform_admin? || current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            result = ::Tenant::OrganizationalNodeLevels::CreateService.call(
              params: declared(params).except(:tenant_id),
              tenant: target_tenant,
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::OrganizationalNodeLevelEntity.represent(result.data),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end
        end
      end
    end
  end
end
