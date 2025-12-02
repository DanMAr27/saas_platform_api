# app/api/v1/tenant/organizational_nodes_tree_api.rb
# API especializada para gestión del árbol organizacional
# Caché eliminada y helpers colocados antes de los endpoints

module V1
  module Tenant
    class OrganizationalNodesTreeApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :organizational_nodes do
          # ---------------------
          # HELPERS (declarados antes de los endpoints)
          # ---------------------
          helpers do
            def resolve_target_tenant(tenant_id_param)
              if current_user.platform_admin? && platform_context?
                unless tenant_id_param
                  api_error(message: "Platform admins must provide tenant_id", status: 400)
                end

                ::Tenant.find_by(id: tenant_id_param) ||
                  api_error(message: "Tenant not found", status: 404)
              else
                require_tenant!
                verify_tenant_access!
                current_tenant
              end
            end

            def find_node_with_tenant(node_id, tenant_id_param)
              node = OrganizationalNode.find_by(id: node_id)
              api_error(message: "Node not found", status: 404) unless node

              unless current_user.platform_admin? ||
                     (current_tenant && node.tenant_id == current_tenant.id)
                api_error(message: "Access denied", status: 403)
              end

              node
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
                tenant_name: tenant.name,
                total_nodes: nodes.count,
                root_nodes: nodes.roots.count,
                leaf_nodes: nodes.leaves.count,
                active_nodes: nodes.active.count,
                # max_depth: nodes.maximum(:depth) || 0,
                generated_at: Time.current.iso8601,
                cache_enabled: false
              }
            end

            def build_node_hash_from_model(node)
              query = OrganizationalNodesTreeQuery.new(
                OrganizationalNode.where(id: node.id).includes(:level, :children)
              )
              query.management_tree.first
            end
          end
          # ---------------------
          # END HELPERS
          # ---------------------

          # ============================================
          # GET /tree - ÁRBOL COMPLETO PARA GESTIÓN
          # ============================================
          desc "Get complete organizational tree",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 200 },
               detail: "Returns the complete organizational hierarchy as a nested tree structure. Used for management and visualization purposes."

          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (required for platform admins)"

            # Filtros opcionales
            optional :status, type: String, values: OrganizationalNode::STATUSES
            optional :level_id, type: Integer
            optional :country, type: String
            optional :city, type: String
            optional :search, type: String

            optional :only_vehicle_nodes, type: Boolean, default: false
            optional :only_user_nodes, type: Boolean, default: false

            optional :sort, type: String, values: %w[name code recent]
          end

          get :tree do
            authenticate!

            # Determinar tenant objetivo
            target_tenant = if current_user.platform_admin? && platform_context?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find_by(id: params[:tenant_id]) ||
                api_error(message: "Tenant not found", status: 404)
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Construir scope base con políticas
            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.includes(:level, :created_by_user),
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            # Construir árbol SIN CACHÉ
            tree_data = build_tree(nodes, target_tenant)

            success_response(
              data: tree_data,
              meta: build_tree_metadata(nodes, target_tenant)
            )
          end

          # ============================================
          # GET /tree/:id - SUBÁRBOL DESDE UN NODO
          # ============================================
          desc "Get subtree from specific node",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 200 },
               detail: "Returns the organizational tree starting from a specific node"

          params do
            requires :id, type: Integer
            optional :tenant_id, type: Integer
          end

          get "tree/:id" do
            authenticate!

            node = find_node_with_tenant(params[:id], params[:tenant_id])
            authorize!(node, :show?, policy_class: OrganizationalNodePolicy)

            query = OrganizationalNodesTreeQuery.new(
              OrganizationalNode.where(tenant_id: node.tenant_id)
            )

            subtree_data = query.subtree(node.id)

            success_response(
              data: V1::Entities::OrganizationalNodeTreeEntity.represent(subtree_data),
              meta: {
                root_node_id: node.id,
                root_node_name: node.name,
                depth: node.depth
              }
            )
          end

          # ============================================
          # GET /tree/stats
          # ============================================
          desc "Get tree statistics",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 200 }

          params do
            optional :tenant_id, type: Integer
          end

          get "tree/stats" do
            authenticate!

            target_tenant = resolve_target_tenant(params[:tenant_id])

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              OrganizationalNode.all
            end

            query = OrganizationalNodesTreeQuery.new(nodes)
            stats = query.tree_stats

            success_response(data: stats)
          end

          # ============================================
          # GET /tree/validate
          # ============================================
          desc "Validate tree integrity",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 200 }

          params do
            optional :tenant_id, type: Integer
          end

          get "tree/validate" do
            authenticate!

            authorize!(:organizational_node, :validate_tree?, policy_class: OrganizationalNodePolicy)

            target_tenant = resolve_target_tenant(params[:tenant_id])

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              OrganizationalNode.all
            end

            query = OrganizationalNodesTreeQuery.new(nodes)
            validation_result = query.validate_tree_integrity

            if validation_result[:valid]
              success_response(
                data: { valid: true },
                message: "Tree structure is valid"
              )
            else
              success_response(
                data: validation_result,
                message: "Tree has integrity issues",
                meta: { errors_count: validation_result[:errors].count }
              )
            end
          end

          # ============================================
          # POST /tree/nodes
          # ============================================
          desc "Create organizational node",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 201 }

          params do
            optional :tenant_id, type: Integer

            requires :name, type: String
            requires :level_id, type: Integer
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

          post "tree/nodes" do
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
                data: V1::Entities::OrganizationalNodeTreeEntity.represent(
                  build_node_hash_from_model(result.data)
                ),
                message: result.message,
                meta: result.meta
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # PATCH /tree/nodes/:id
          # ============================================
          desc "Update organizational node",
               tags: [ "Tenant - Organizational Tree" ],
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
            optional :metadata, type: Hash
          end

          patch "tree/nodes/:id" do
            authenticate!

            node = find_node_with_tenant(params[:id], params[:tenant_id])
            authorize!(node, :update?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::UpdateService.call(
              node: node,
              params: declared(params).except(:id, :tenant_id),
              current_user: current_user
            )

            if result.success?
              success_response(
                data: V1::Entities::OrganizationalNodeTreeEntity.represent(
                  build_node_hash_from_model(result.data)
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # PATCH /tree/nodes/:id/move
          # ============================================
          desc "Move node to different parent",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 200 }

          params do
            requires :id, type: Integer
            requires :parent_id, type: Integer, allow_blank: true
          end

          patch "tree/nodes/:id/move" do
            authenticate!

            node = find_node_with_tenant(params[:id], params[:tenant_id])
            authorize!(node, :move?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::MoveService.call(
              node: node,
              new_parent_id: params[:parent_id],
              current_user: current_user
            )

            if result.success?
              success_response(
                data: V1::Entities::OrganizationalNodeTreeEntity.represent(
                  build_node_hash_from_model(result.data)
                ),
                message: result.message,
                meta: result.meta
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # DELETE /tree/nodes/:id
          # ============================================
          desc "Delete organizational node",
               tags: [ "Tenant - Organizational Tree" ],
               success: { code: 200 }

          params do
            requires :id, type: Integer
          end

          delete "tree/nodes/:id" do
            authenticate!

            node = find_node_with_tenant(params[:id], params[:tenant_id])
            authorize!(node, :destroy?, policy_class: OrganizationalNodePolicy)

            result = ::Tenants::OrganizationalNodes::DestroyService.call(
              node: node,
              current_user: current_user
            )

            if result.success?
              success_response(message: result.message, meta: result.meta)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end
        end
      end
    end
  end
end
