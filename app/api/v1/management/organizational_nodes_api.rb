# app/api/v1/management/organizational_nodes_api.rb
# API REST unificada para gestión de nodos organizacionales (Flat & Tree)

module V1
  module Management
    class OrganizationalNodesApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::ManagementHelper
      helpers Helpers::AuthorizationHelper

      namespace :management do
        namespace :organizational_nodes do
          # ============================================
          # HELPER LOCALES (Integrados de TreeApi)
          # ============================================
          helpers do
            def resolve_target_tenant(tenant_id_param)
              if current_user.platform_admin? && platform_context?
                unless tenant_id_param
                  api_error(message: "Platform admins must provide tenant_id", status: 400)
                end
                ::Tenant.find_by(id: tenant_id_param) || api_error(message: "Tenant not found", status: 404)
              else
                require_tenant!
                verify_tenant_access!
                current_tenant
              end
            end

            def build_tree(nodes, tenant)
              query = OrganizationalNodesTreeQuery.new(
                nodes,
                params: declared(params, include_missing: false),
                user: current_user
              )
              tree = query.management_tree
              V1::Entities::OrganizationalNodeTreeEntity.represent(tree)
            end

            def build_tree_metadata(nodes, tenant)
              {
                tenant_id: tenant.id,
                total_nodes: nodes.count,
                root_nodes: nodes.roots.count,
                active_nodes: nodes.active.count,
                generated_at: Time.current.iso8601
              }
            end
          end

          # ============================================
          # LISTAR NODOS (Unified Endpoint)
          # ============================================
          desc "List organizational nodes",
                tags: [ "Management - Organizational Nodes" ],
                success: { code: 200 },
                detail: "Returns organizational structure. Supports 'flat', 'tree', and 'dropdown' views."
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (required for platform admins)"
            optional :view, type: String, values: %w[flat tree], default: "flat", desc: "Response format"

            # Filtros comunes
            optional :status, type: String, values: OrganizationalNode::STATUSES
            optional :level_id, type: Integer
            optional :parent_id, type: Integer
            optional :search, type: String

            # Filtros de capacidades
            optional :allows_vehicles, type: Boolean
            optional :allows_users, type: Boolean

            # Opciones específicas de vista
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25
            optional :sort, type: String
          end
          get do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])

            # Scope base
            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.includes(:level, :parent),
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            # ------------------------------------------------
            # VISTA: TREE (Árbol Jerárquico Completo)
            # ------------------------------------------------
            if params[:view] == "tree"
              tree_data = build_tree(nodes, target_tenant)
              success_response(
                data: tree_data,
                meta: build_tree_metadata(nodes, target_tenant)
              )

            # ------------------------------------------------
            # VISTA: FLAT (Listado Plano Paginado - Default)
            # ------------------------------------------------
            else
              query = OrganizationalNodesQuery.new(nodes, params: declared(params), user: current_user)

              # Soporte legacy para tree=true en flat view (si el frontend lo usaba)
              if params[:tree] == true
                 tree_data = query.tree_with_paths(params[:parent_id])
                 success_response(data: tree_data)
              else
                paginated_nodes = query.call.page(params[:page]).per(params[:per_page])
                success_response(
                  data: paginated_nodes.map { |n|
                    Entities::OrganizationalNodeEntity.represent(
                      n,
                      show_details: true,
                      include_level: true,
                      include_path: true
                    )
                  },
                  meta: {
                    current_page: paginated_nodes.current_page,
                    total_pages: paginated_nodes.total_pages,
                    total_count: paginated_nodes.total_count
                  }
                )
              end
            end
          end

          # ============================================
          # VER NODO
          # ============================================
          desc "Get organizational node details",
                tags: [ "Management - Organizational Nodes" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
          end
          get ":id" do
            authenticate!
            node = OrganizationalNode.find(params[:id])

            # Validación de acceso manual o via policy scope
            unless current_user.platform_admin? || (current_tenant && node.tenant_id == current_tenant.id)
               api_error(message: "Node not found or access denied", status: 404)
            end
            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            present node,
                    with: Entities::OrganizationalNodeEntity,
                    show_details: true,
                    include_level: true,
                    include_path: true
          end

          # ============================================
          # CREAR NODO
          # ============================================
          desc "Create organizational node",
                tags: [ "Management - Organizational Nodes" ],
                success: { code: 201 }
          params do
            optional :tenant_id, type: Integer
            requires :name, type: String
            optional :parent_id, type: Integer
            optional :code, type: String
            optional :description, type: String
            optional :address, type: String
            optional :city, type: String
            optional :state, type: String
            optional :postal_code, type: String
            optional :country, type: String
            optional :phone, type: String
            optional :email, type: String
            optional :status, type: String, values: OrganizationalNode::STATUSES, default: "active"
            optional :metadata, type: Hash
          end
          post do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])

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
                  include_path: true
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
                tags: [ "Management - Organizational Nodes" ],
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
            optional :status, type: String
            optional :metadata, type: Hash
          end
          patch ":id" do
            authenticate!
            node = OrganizationalNode.find(params[:id])

            # Check tenant access implicitly via Pundit or explicit check
            unless current_user.platform_admin? || (current_tenant && node.tenant_id == current_tenant.id)
               api_error(message: "Node not found", status: 404)
            end

            authorize!(node, :update?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::UpdateService.call(
              node: node,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::OrganizationalNodeEntity.represent(result.data, include_path: true),
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
                tags: [ "Management - Organizational Nodes" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            requires :parent_id, type: Integer, allow_blank: true
          end
          patch ":id/move" do
            authenticate!
            node = OrganizationalNode.find(params[:id])
             unless current_user.platform_admin? || (current_tenant && node.tenant_id == current_tenant.id)
               api_error(message: "Node not found", status: 404)
             end

            authorize!(node, :move?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::MoveService.call(
              node: node,
              new_parent_id: params[:parent_id],
              current_user: current_user
            )

            if result.success?
              success_response(data: result.data, message: result.message)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ELIMINAR NODO
          # ============================================
          desc "Delete organizational node",
                tags: [ "Management - Organizational Nodes" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
          end
          delete ":id" do
            authenticate!
            node = OrganizationalNode.find(params[:id])
             unless current_user.platform_admin? || (current_tenant && node.tenant_id == current_tenant.id)
               api_error(message: "Node not found", status: 404)
             end

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
          # ESTADISTICAS Y UTILIDADES
          # ============================================

          desc "Get structure statistics", tags: [ "Management - Organizational Nodes" ]
          params { optional :tenant_id, type: Integer }
          get "stats/overview" do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])
            nodes = ActsAsTenant.with_tenant(target_tenant) { OrganizationalNode.all }
            query = OrganizationalNodesQuery.new(nodes)
            success_response(data: query.stats)
          end

          desc "Validate path", tags: [ "Management - Organizational Nodes" ]
          params { requires :path_ids, type: Array[Integer] }
          post "validate_path" do
            authenticate!
            require_tenant!
            nodes = ActsAsTenant.with_tenant(current_tenant) { OrganizationalNode.all }
            result = OrganizationalNodesQuery.new(nodes).validate_path(params[:path_ids])

            result[:valid] ? success_response(data: result) : api_error(message: result[:error], status: 422)
          end

          desc "Get node ancestors", tags: [ "Management - Organizational Nodes" ]
          get ":id/ancestors" do
            authenticate!
            node = OrganizationalNode.find(params[:id])
            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)
            success_response(data: node.ancestor_chain.map { |n| Entities::OrganizationalNodeEntity.represent(n) })
          end
        end
      end
    end
  end
end
