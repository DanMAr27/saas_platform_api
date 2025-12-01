# app/api/v1/tenant/roles_api.rb

module V1
  module Tenant
    # API para consultar roles disponibles en el tenant
    # ACTUALIZADO: Con soporte para scope flags
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
                detail: "Returns roles that can be assigned to users in the tenant with scope requirements"
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            optional :include_usage, type: Boolean, default: false, desc: "Include usage statistics"
            optional :scope_filter, type: String, values: %w[all no_scope node_scope vehicle_scope],
                     default: "all", desc: "Filter roles by scope type"
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

            # 🆕 NUEVO: Filtrar por tipo de scope
            case params[:scope_filter]
            when "no_scope"
              roles = roles.without_scope_requirements
            when "node_scope"
              roles = roles.requiring_node_scopes
            when "vehicle_scope"
              roles = roles.requiring_vehicle_scopes
            end

            # Preparar opciones para entity
            entity_options = {
              show_usage: params[:include_usage],
              tenant_id: target_tenant&.id
            }

            success_response(
              data: Entities::RoleEntity.represent(roles, entity_options),
              meta: {
                total: roles.count,
                tenant_id: target_tenant&.id,
                filter_applied: params[:scope_filter],
                scope_distribution: Role.tenant_roles.scope_distribution
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
            optional :include_usage, type: Boolean, default: true
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

            entity_options = {
              show_settings: true,
              show_timestamps: true,
              show_usage: params[:include_usage],
              tenant_id: target_tenant&.id
            }

            success_response(
              data: Entities::RoleEntity::Detailed.represent(role, entity_options)
            )
          end

          # ============================================
          # 🆕 NUEVO: OBTENER ROLES DISPONIBLES PARA ASIGNACIÓN
          # ============================================
          desc "Get roles available for user assignment",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 },
                detail: "Returns simplified role list suitable for dropdowns/selects"
          params do
            optional :tenant_id, type: Integer
          end
          get "available/for_assignment" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Solo admins pueden ver esta info
            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            # Usar el método del modelo
            roles_info = Role.available_for_assignment(context: "tenant")

            success_response(
              data: roles_info,
              message: "Available roles for assignment"
            )
          end

          # ============================================
          # 🆕 NUEVO: VALIDAR COMPATIBILIDAD ROL-SCOPE
          # ============================================
          desc "Validate role-scope compatibility",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 },
                detail: "Check if provided scopes are compatible with a role"
          params do
            requires :role_slug, type: String
            optional :node_scopes, type: Array do
              requires :organizational_node_id, type: Integer
            end
            optional :vehicle_scopes, type: Array do
              requires :vehicle_id, type: Integer
            end
          end
          post "validate_scopes" do
            authenticate!

            role = Role.tenant_roles.find_by(slug: params[:role_slug])
            unless role
              api_error(message: "Role not found", status: 404)
            end

            # Validar compatibilidad usando el concern Scopeable
            validation = role.validate_scope_compatibility(
              node_scopes: params[:node_scopes],
              vehicle_scopes: params[:vehicle_scopes]
            )

            if validation[:valid]
              success_response(
                data: {
                  valid: true,
                  role: params[:role_slug],
                  message: "Scopes are compatible with this role"
                }
              )
            else
              success_response(
                data: {
                  valid: false,
                  role: params[:role_slug],
                  errors: validation[:errors]
                },
                status: 200  # No es error del servidor, es validación
              )
            end
          end

          # ============================================
          # PERMISOS DE ROL (ACTUALIZADO)
          # ============================================
          desc "Get role permissions description",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 },
                detail: "Returns human-readable description of what each role can do"
          get "permissions/summary" do
            authenticate!

            permissions = {
              tenant_admin: {
                slug: "tenant_admin",
                name: "Tenant Admin",
                description: "Full control over the tenant",
                scope_requirements: {
                  requires_any_scope: false,
                  allows_node_scope: false,
                  allows_vehicle_scope: false,
                  description: "No scopes required (full access)"
                },
                can_do: [
                  "Manage all users (create, edit, delete, suspend)",
                  "Assign and modify user roles",
                  "Manage node and vehicle scopes for other users",
                  "Configure tenant settings",
                  "View all reports and statistics",
                  "Manage organizational structure",
                  "Manage fleet vehicles",
                  "Access all nodes and vehicles without restrictions"
                ],
                cannot_do: [
                  "Delete the primary admin account",
                  "Access other tenants (isolated per tenant)"
                ]
              },
              tenant_manager: {
                slug: "tenant_manager",
                name: "Tenant Manager",
                description: "Manages users and operations within assigned nodes",
                scope_requirements: {
                  requires_any_scope: true,
                  allows_node_scope: true,
                  allows_vehicle_scope: false,
                  description: "Requires: node access"
                },
                can_do: [
                  "View all users in assigned nodes",
                  "Invite new users to assigned nodes",
                  "Assign scopes to users within their nodes",
                  "View reports and statistics for assigned nodes",
                  "Manage vehicles within assigned nodes",
                  "View all vehicles (read-only) across tenant"
                ],
                cannot_do: [
                  "Change user roles",
                  "Delete users",
                  "Access nodes outside their scope",
                  "Modify organizational structure",
                  "Change tenant settings"
                ]
              },
              tenant_driver: {
                slug: "tenant_driver",
                name: "Tenant Driver",
                description: "Operates vehicles and views assigned data",
                scope_requirements: {
                  requires_any_scope: true,
                  allows_node_scope: false,
                  allows_vehicle_scope: true,
                  description: "Requires: vehicle access"
                },
                can_do: [
                  "View own profile",
                  "View assigned vehicles",
                  "Operate assigned vehicles (if granted drive access)",
                  "Create trips for assigned vehicles",
                  "View basic reports for assigned vehicles",
                  "View assigned vehicle locations and status"
                ],
                cannot_do: [
                  "Manage other users",
                  "Access vehicles not assigned to them",
                  "Modify organizational structure",
                  "View sensitive tenant information",
                  "Access nodes directly"
                ]
              }
            }

            success_response(
              data: permissions,
              message: "Role permissions summary",
              meta: {
                total_roles: permissions.keys.count,
                context: "tenant"
              }
            )
          end

          # ============================================
          # 🆕 NUEVO: SCOPE REQUIREMENTS POR ROL
          # ============================================
          desc "Get scope requirements for all roles",
                tags: [ "Tenant - Roles" ],
                success: { code: 200 },
                detail: "Quick reference of what scopes each role needs"
          get "scope_requirements" do
            authenticate!

            requirements = Role.tenant_roles.by_priority.map do |role|
              {
                slug: role.slug,
                name: role.name,
                requires_any_scope: role.requires_any_scope?,
                allows_node_scope: role.allows_node_scope?,
                allows_vehicle_scope: role.allows_vehicle_scope?,
                scope_type: role.scope_type,
                description: role.scope_requirements_description,
                example: scope_example_for_role(role)
              }
            end

            success_response(
              data: requirements,
              message: "Scope requirements for all tenant roles"
            )
          end
        end
      end

      # ============================================
      # HELPER METHODS
      # ============================================
      helpers do
        def scope_example_for_role(role)
          return nil unless role.requires_any_scope?

          if role.allows_node_scope?
            {
              node_scopes: [
                {
                  organizational_node_id: 1,
                  access_type: "write",
                  include_children: true
                }
              ]
            }
          elsif role.allows_vehicle_scope?
            {
              vehicle_scopes: [
                {
                  vehicle_id: 1,
                  access_type: "drive",
                  valid_from: Time.current.iso8601,
                  valid_until: 1.year.from_now.iso8601
                }
              ]
            }
          end
        end
      end
    end
  end
end
