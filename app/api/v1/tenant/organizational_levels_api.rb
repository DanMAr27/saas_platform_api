# app/api/v1/tenant/organizational_levels_api.rb
# 🆕 NUEVO ARCHIVO: API REST para gestión de niveles organizacionales
# Separado de organizational_nodes_api para mejor organización y mantenimiento

module V1
  module Tenant
    class OrganizationalLevelsApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :organizational_levels do
          # ============================================
          # LISTAR NIVELES
          # ============================================
          desc "List organizational levels",
                tags: [ "Tenant - Organizational Levels" ],
                success: { code: 200 },
                detail: "Returns all organizational hierarchy levels configured for the tenant"
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (required for platform admins)"
            optional :is_system, type: Boolean, desc: "Filter system levels"
            optional :allows_vehicles, type: Boolean, desc: "Filter levels that allow vehicles"
            optional :allows_users, type: Boolean, desc: "Filter levels that allow users"
            optional :sort, type: String, values: %w[name order], default: "order"
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
              },
              meta: {
                total_count: levels.count
              }
            )
          end

          # ============================================
          # VER NIVEL
          # ============================================
          desc "Get organizational level details",
                tags: [ "Tenant - Organizational Levels" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer, desc: "Level ID"
          end
          get ":id" do
            authenticate!

            level = OrganizationalNodeLevel.find(params[:id])

            unless current_user.platform_admin? ||
                   (current_tenant && level.tenant_id == current_tenant.id)
              api_error(message: "Level not found or access denied", status: 404)
            end

            authorize!(level, :show?, policy_class: OrganizationalNodeLevelPolicy)

            present level,
                    with: Entities::OrganizationalNodeLevelEntity,
                    show_timestamps: true
          end

          # ============================================
          # CREAR NIVEL
          # ============================================
          desc "Create organizational level",
                tags: [ "Tenant - Organizational Levels" ],
                success: { code: 201 },
                detail: "Creates a new hierarchy level. Only admins can create levels."
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            requires :name, type: String, desc: "Level name (e.g., Branch, Division, Department)"
            optional :slug, type: String, desc: "URL-friendly identifier"
            optional :description, type: String
            requires :level_order, type: Integer, desc: "Hierarchical order (1 = highest level)"
            optional :allows_vehicles, type: Boolean, default: true, desc: "Can nodes of this level have vehicles?"
            optional :allows_users, type: Boolean, default: true, desc: "Can nodes of this level have users?"
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

            # Solo admins pueden crear niveles
            unless current_user.platform_admin? || current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            temp_level = OrganizationalNodeLevel.new(tenant: target_tenant)
            authorize!(temp_level, :create?, policy_class: OrganizationalNodeLevelPolicy)

            result = ::Tenants::OrganizationalNodeLevels::CreateService.call(
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

          # ============================================
          # ACTUALIZAR NIVEL
          # ============================================
          desc "Update organizational level",
                tags: [ "Tenant - Organizational Levels" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :name, type: String
            optional :slug, type: String
            optional :description, type: String
            optional :level_order, type: Integer
            optional :allows_vehicles, type: Boolean
            optional :allows_users, type: Boolean
          end
          patch ":id" do
            authenticate!

            level = OrganizationalNodeLevel.find(params[:id])

            unless current_user.platform_admin? ||
                   (current_tenant && level.tenant_id == current_tenant.id)
              api_error(message: "Level not found or access denied", status: 404)
            end

            authorize!(level, :update?, policy_class: OrganizationalNodeLevelPolicy)

            result = ::Tenants::OrganizationalNodeLevels::UpdateService.call(
              level: level,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::OrganizationalNodeLevelEntity.represent(result.data),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ELIMINAR NIVEL
          # ============================================
          desc "Delete organizational level",
                tags: [ "Tenant - Organizational Levels" ],
                success: { code: 200 },
                detail: "Soft deletes a level. Cannot delete if nodes exist at this level."
          params do
            requires :id, type: Integer
          end
          delete ":id" do
            authenticate!

            level = OrganizationalNodeLevel.find(params[:id])

            unless current_user.platform_admin? ||
                   (current_tenant && level.tenant_id == current_tenant.id)
              api_error(message: "Level not found or access denied", status: 404)
            end

            authorize!(level, :destroy?, policy_class: OrganizationalNodeLevelPolicy)

            result = ::Tenants::OrganizationalNodeLevels::DestroyService.call(
              level: level,
              current_user: current_user
            )

            if result.success?
              success_response(message: result.message)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # 🆕 NUEVO: REORDENAR NIVELES
          # ✏️ CORREGIDO: Sintaxis correcta de params para Grape
          # ============================================
          desc "Reorder organizational levels",
                tags: [ "Tenant - Organizational Levels" ],
                success: { code: 200 },
                detail: "Updates the hierarchical order of multiple levels at once"
          params do
            # ✅ CORRECCIÓN: Usar Array[JSON] en lugar de Array[Hash]
            requires :levels, type: Array[JSON], desc: "Array of level objects with id and level_order" do
              requires :id, type: Integer, desc: "Level ID"
              requires :level_order, type: Integer, desc: "New level order"
            end
          end
          post "reorder" do
            authenticate!
            require_tenant!

            unless current_user.platform_admin? || current_user.tenant_admin?(current_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            result = ::Tenants::OrganizationalNodeLevels::ReorderService.call(
              levels_data: params[:levels],
              tenant: current_tenant,
              current_user: current_user
            )

            if result.success?
              success_response(
                data: result.data.map { |l|
                  Entities::OrganizationalNodeLevelEntity.represent(l)
                },
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # 🆕 NUEVO: ESTADÍSTICAS DE NIVELES
          # ============================================
          desc "Get level usage statistics",
                tags: [ "Tenant - Organizational Levels" ],
                detail: "Returns statistics about how many nodes exist at each level"
          params do
            optional :tenant_id, type: Integer
          end
          get "stats/usage" do
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
              OrganizationalNodeLevel.includes(:nodes).all
            end

            stats = levels.map do |level|
              {
                level_id: level.id,
                name: level.name,
                level_order: level.level_order,
                nodes_count: level.nodes.count,
                active_nodes_count: level.nodes.active.count,
                allows_vehicles: level.allows_vehicles,
                allows_users: level.allows_users
              }
            end

            success_response(
              data: stats,
              meta: {
                total_levels: levels.count,
                total_nodes: stats.sum { |s| s[:nodes_count] }
              }
            )
          end
        end
      end
    end
  end
end
