# app/api/v1/tenant/roles_api.rb

module V1
  module Tenant
    # API para consultar roles disponibles en el tenant
    class RolesApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :roles do
          # ============================================
          # LISTAR ROLES DISPONIBLES
          # ============================================
          desc "List available roles for tenant",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 },
                detail: "Returns roles that can be assigned to users in the tenant"
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            optional :include_usage, type: Boolean, default: false
          end
          get do
            authenticate!

            # Determinar tenant
            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : nil
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Obtener roles de tenant
            roles = Role.tenant_roles.by_priority

            # Incluir estadísticas de uso si se solicita
            data = roles.map do |role|
              role_data = {
                id: role.id,
                name: role.name,
                slug: role.slug,
                description: role.description,
                requires_scope: role.requires_scope,
                is_system: role.is_system,
                priority: role.priority
              }

              if params[:include_usage] && target_tenant
                role_data[:usage_count] = target_tenant.tenant_memberships
                                                      .where(role_id: role.id)
                                                      .kept
                                                      .count
              end

              role_data
            end

            success_response(
              data: data,
              meta: {
                total: roles.count,
                tenant_id: target_tenant&.id
              }
            )
          end

          # ============================================
          # VER DETALLES DE ROL
          # ============================================
          desc "Get role details",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 }
          params do
            requires :slug, type: String, desc: "Role slug"
            optional :tenant_id, type: Integer
          end
          get ":slug" do
            authenticate!

            role = Role.tenant_roles.find_by(slug: params[:slug])
            unless role
              api_error(message: "Role not found", status: 404)
            end

            # Determinar tenant para estadísticas
            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : nil
            else
              current_tenant
            end

            data = {
              id: role.id,
              name: role.name,
              slug: role.slug,
              description: role.description,
              context: role.context,
              requires_scope: role.requires_scope,
              is_system: role.is_system,
              priority: role.priority,
              settings: role.settings,
              created_at: role.created_at.iso8601,
              updated_at: role.updated_at.iso8601
            }

            # Estadísticas de uso en el tenant
            if target_tenant
              data[:usage_in_tenant] = {
                total_users: target_tenant.tenant_memberships
                                         .where(role_id: role.id)
                                         .kept
                                         .count,
                active_users: target_tenant.tenant_memberships
                                          .where(role_id: role.id, status: "active")
                                          .kept
                                          .count
              }
            end

            success_response(data: data)
          end

          # ============================================
          # PERMISOS DE ROL
          # ============================================
          desc "Get role permissions description",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 },
                detail: "Returns human-readable description of what each role can do"
          get "permissions/summary" do
            authenticate!

            permissions = {
              tenant_admin: {
                name: "Tenant Admin",
                description: "Full control over the tenant",
                can_do: [
                  "Manage all users (create, edit, delete, suspend)",
                  "Assign and modify user roles",
                  "Manage node and vehicle scopes",
                  "Configure tenant settings",
                  "View all reports and statistics",
                  "Manage organizational structure",
                  "Manage fleet vehicles",
                  "Cannot delete primary admin"
                ],
                requires_scope: false
              },
              tenant_manager: {
                name: "Tenant Manager",
                description: "Manages users and operations",
                can_do: [
                  "View all users",
                  "Invite new users",
                  "Assign node and vehicle scopes",
                  "View reports and statistics",
                  "Manage assigned vehicles and nodes",
                  "Cannot change user roles",
                  "Cannot delete users"
                ],
                requires_scope: false
              },
              tenant_driver: {
                name: "Tenant Driver",
                description: "Operates vehicles and views assigned data",
                can_do: [
                  "View own profile",
                  "View assigned vehicles",
                  "View assigned organizational nodes",
                  "Operate assigned vehicles (if granted drive access)",
                  "View basic reports for assigned resources",
                  "Cannot manage other users",
                  "Cannot modify organizational structure"
                ],
                requires_scope: true
              }
            }

            success_response(
              data: permissions,
              message: "Role permissions summary"
            )
          end
        end
      end
    end
  end
end
