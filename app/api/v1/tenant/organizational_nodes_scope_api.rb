# app/api/v1/tenant/organizational_nodes_scope_api.rb

module V1
  module Tenant
    class OrganizationalNodesScopeApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :organizational_nodes do
          # ============================================
          # HELPERS LOCALES
          # ============================================
          helpers do
            # Resolver tenant objetivo
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

            # Encontrar usuario objetivo (si se proporcionó)
            def find_user(user_id, tenant)
              user = User.find_by(id: user_id)
              api_error(message: "User not found", status: 404) unless user

              unless user.tenant_memberships.exists?(tenant_id: tenant.id)
                api_error(message: "User doesn't belong to this tenant", status: 403)
              end

              user
            end

            # Autorizar acceso a scopes (solo cuando target_user presente)
            def authorize_scope_access!(target_user, tenant)
              return if current_user.platform_admin?
              return if current_user.tenant_admin?(tenant.id)
              return if target_user && current_user.id == target_user.id
              # Managers: implementar jerarquía si existe (aquí puedes expandir la lógica)
              api_error(message: "Not authorized to view this user's scopes", status: 403)
            end

            # Aplicar filtros al árbol de selección
            def apply_selection_filters(nodes)
              nodes = nodes.where(status: params[:status]) if params[:status]
              nodes = nodes.where(level_id: params[:level_id]) if params[:level_id]

              if params[:only_vehicle_nodes]
                nodes = nodes.joins(:level)
                             .where(organizational_node_levels: { allows_vehicles: true })
              end

              if params[:only_user_nodes]
                nodes = nodes.joins(:level)
                             .where(organizational_node_levels: { allows_users: true })
              end

              if params[:search].present?
                term = "%#{params[:search].downcase}%"
                nodes = nodes.where("LOWER(organizational_nodes.name) LIKE :term OR LOWER(organizational_nodes.code) LIKE :term", term: term)
              end

              nodes
            end

            # Construir árbol con información de selección (soporta user = nil)
            def build_selection_tree(nodes, user, tenant)
              # Construir cache key de forma segura aunque user sea nil
              user_part = user&.id || "none"
              cache_key = "tenant:#{tenant.id}:user:#{user_part}:selection_tree:#{selection_cache_key_suffix}"

              # Si no queremos cache, delegar directamente
              if params[:no_cache]
                OrganizationalNodesScopeQuery.new(nodes, user: user).selection_tree
              else
                Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
                  OrganizationalNodesScopeQuery.new(nodes, user: user).selection_tree
                end
              end
            end

            # Sufijo para cache key basado en filtros
            def selection_cache_key_suffix
              parts = []
              parts << "status:#{params[:status]}" if params[:status]
              parts << "level:#{params[:level_id]}" if params[:level_id]
              parts << "vehicles" if params[:only_vehicle_nodes]
              parts << "users" if params[:only_user_nodes]
              parts << "search:#{Digest::MD5.hexdigest(params[:search])}" if params[:search]
              parts.any? ? parts.join(":") : "default"
            end
          end

          # ============================================
          # GET /selection_tree - ÁRBOL PARA ASIGNACIÓN DE SCOPES
          # ============================================
          # Endpoint principal para mostrar el árbol con información
          # de selección de un usuario o, si no se pasa usuario,
          # para mostrar el árbol completo sin selecciones.
          desc "Get organizational tree with user scope information",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            optional :tenant_id, type: Integer
            optional :user_id, type: Integer         # <-- ahora opcional
            optional :status, type: String, values: OrganizationalNode::STATUSES
            optional :level_id, type: Integer
            optional :only_vehicle_nodes, type: Boolean, default: false
            optional :only_user_nodes, type: Boolean, default: false
            optional :search, type: String
            optional :no_cache, type: Boolean, default: false
          end
          get :selection_tree do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])

            # Si user_id está presente, buscar y autorizar; si no, trabajamos en modo "creación"
            target_user = nil
            if params[:user_id].present?
              target_user = find_user(params[:user_id], target_tenant)
              # autorizar sólo si existe target_user
              authorize_scope_access!(target_user, target_tenant)
            end

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.active.includes(:level, :children, :ancestors),
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            nodes = apply_selection_filters(nodes)
            tree_data = build_selection_tree(nodes, target_user, target_tenant)

            success_response(
              data: V1::Entities::OrganizationalNodeSelectionEntity.represent(tree_data[:tree]),
              meta: V1::Entities::OrganizationalNodeSelectionEntity::SelectionTreeMetadataEntity.represent(tree_data[:metadata])
            )
          end

          # ============================================
          # GET /users/:user_id/scopes - OBTENER SCOPES DE UN USUARIO
          # ============================================
          desc "Get user's current organizational scopes",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            requires :user_id, type: Integer
            optional :tenant_id, type: Integer
            optional :include_effective, type: Boolean, default: false
          end
          get "users/:user_id/scopes" do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])
            target_user = find_user(params[:user_id], target_tenant)
            authorize_scope_access!(target_user, target_tenant)

            stored_scopes = UserNodeScope
              .where(user_id: target_user.id, tenant_id: target_tenant.id)
              .includes(organizational_node: [ :level, :ancestors ])
            stored_ids = stored_scopes.pluck(:organizational_node_id)

            response_data = {
              user_id: target_user.id,
              user_email: target_user.email,
              tenant_id: target_tenant.id,
              stored_scopes: stored_scopes.map do |scope|
                {
                  id: scope.organizational_node_id,
                  name: scope.organizational_node.name,
                  full_path: scope.organizational_node.full_path,
                  level: scope.organizational_node.level.name,
                  created_at: scope.created_at
                }
              end
            }

            if params[:include_effective]
              query = OrganizationalNodesScopeQuery.new(OrganizationalNode.where(tenant_id: target_tenant.id), user: target_user)
              effective_ids = query.expand_to_effective_ids(stored_ids)
              response_data[:effective_coverage] = { node_count: effective_ids.count, node_ids: effective_ids }
              response_data[:optimization] = {
                stored_count: stored_ids.count,
                effective_count: effective_ids.count,
                saved_records: effective_ids.count - stored_ids.count,
                percentage: ((effective_ids.count - stored_ids.count).to_f / effective_ids.count * 100).round(1)
              }
            end

            success_response(data: response_data)
          end

          # ============================================
          # PUT /users/:user_id/scopes - ACTUALIZAR SCOPES
          # ============================================
          desc "Update user's organizational scopes",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            requires :user_id, type: Integer
            optional :tenant_id, type: Integer
            requires :node_ids, type: Array[Integer]
          end
          put "users/:user_id/scopes" do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])
            target_user = find_user(params[:user_id], target_tenant)

            authorize!(:user_node_scope, :update?, policy_class: UserNodeScopePolicy)

            result = ::Tenants::UserNodeScopes::UpdateService.call(
              user: target_user,
              tenant: target_tenant,
              node_ids: params[:node_ids],
              current_user: current_user
            )

            if result.success?
              success_response(data: result.data, message: result.message, meta: result.meta)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # DELETE /users/:user_id/scopes - LIMPIAR SCOPES
          # ============================================
          desc "Clear all user's organizational scopes",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            requires :user_id, type: Integer
            optional :tenant_id, type: Integer
          end
          delete "users/:user_id/scopes" do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])
            target_user = find_user(params[:user_id], target_tenant)

            authorize!(:user_node_scope, :destroy?, policy_class: UserNodeScopePolicy)

            result = ::Tenants::UserNodeScopes::ClearService.call(
              user: target_user,
              tenant: target_tenant,
              current_user: current_user
            )

            if result.success?
              success_response(message: result.message, meta: result.meta)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # GET /dropdown_options - OPCIONES PARA DROPDOWN
          # ============================================
          desc "Get dropdown options for organizational nodes",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            optional :tenant_id, type: Integer
            optional :only_vehicles, type: Boolean, default: false
            optional :current_user_scope, type: Boolean, default: false
          end
          get :dropdown_options do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])

            nodes = ActsAsTenant.with_tenant(target_tenant) do
              OrganizationalNode.active.includes(:level, ancestors: :level)
            end

            if params[:current_user_scope]
              query = OrganizationalNodesScopeQuery.new(nodes, user: current_user)
              effective_ids = query.user_effective_scope_ids
              nodes = nodes.where(id: effective_ids)
            end

            query = OrganizationalNodesScopeQuery.new(nodes)
            options = query.dropdown_options(only_vehicles: params[:only_vehicles])

            success_response(
              data: options,
              meta: { total_options: options.count, filtered_by_user_scope: params[:current_user_scope] }
            )
          end

          # ============================================
          # POST /users/:user_id/scopes/validate_access - VALIDAR ACCESO
          # ============================================
          desc "Validate if user has access to specific node",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            requires :user_id, type: Integer
            requires :node_id, type: Integer
            optional :tenant_id, type: Integer
          end
          post "users/:user_id/scopes/validate_access" do
            authenticate!

            target_tenant = resolve_target_tenant(params[:tenant_id])
            target_user = find_user(params[:user_id], target_tenant)

            result = ::Tenants::UserNodeScopes::ValidateAccessService.call(
              user: target_user,
              node_id: params[:node_id]
            )

            if result.success?
              success_response(data: result.data)
            else
              api_error(message: result.message, status: 422)
            end
          end

          # ============================================
          # POST /users/bulk_update_scopes - ACTUALIZACIÓN MASIVA
          # ============================================
          desc "Bulk update scopes for multiple users",
               tags: [ "Tenant - User Scopes" ],
               success: { code: 200 }
          params do
            requires :user_ids, type: Array[Integer], desc: "Array of user IDs"
            requires :node_ids, type: Array[Integer], desc: "Array of node IDs to assign"
            optional :tenant_id, type: Integer
          end
          post "users/bulk_update_scopes" do
            authenticate!
            target_tenant = resolve_target_tenant(params[:tenant_id])
            authorize!(:user_node_scope, :bulk_update?, policy_class: UserNodeScopePolicy)

            users = User.where(id: params[:user_ids])
            unless users.count == params[:user_ids].count
              api_error(message: "Some users not found", status: 404)
            end

            result = ::Tenants::UserNodeScopes::BulkUpdateService.call(
              users: users,
              tenant: target_tenant,
              node_ids: params[:node_ids],
              current_user: current_user
            )

            if result.success?
              success_response(data: result.data, message: result.message, meta: result.meta)
            else
              api_error(message: result.message, data: result.data, status: 422)
            end
          end
        end
      end
    end
  end
end
