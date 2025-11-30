# app/api/v1/tenant/users_api.rb

module V1
  module Tenant
    class UsersApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :users do
          # ============================================
          # LISTAR USUARIOS DEL TENANT
          # ============================================
          desc "List users in current tenant",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            optional :status, type: String, values: TenantMembership::STATUSES
            optional :role_slug, type: String
            optional :search, type: String, desc: "Search by name or email"
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25, values: 1..100
          end
          get do
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
            unless current_user.platform_admin? ||
                  current_user.tenant_admin?(target_tenant.id) ||
                  current_user.tenant_manager?(target_tenant.id)
              api_error(message: "Admin or Manager role required", status: 403)
            end

            # ✅ PARTIR DE USERS, NO DE MEMBERSHIPS
            users_query = ::User.kept
                                .joins(:tenant_memberships)
                                .where(tenant_memberships: {
                                  tenant_id: target_tenant.id,
                                  deleted_at: nil
                                })
                                .distinct

            # Aplicar filtros
            if params[:status].present?
              users_query = users_query.where(tenant_memberships: { status: params[:status] })
            end

            if params[:role_slug].present?
              users_query = users_query.joins(tenant_memberships: :role)
                                      .where(
                                        tenant_memberships: { tenant_id: target_tenant.id },
                                        roles: { slug: params[:role_slug] }
                                      )
            end

            if params[:search].present?
              search_term = "%#{params[:search].downcase}%"
              users_query = users_query.where(
                "LOWER(users.email) LIKE ? OR
                LOWER(users.first_name) LIKE ? OR
                LOWER(users.last_name) LIKE ?",
                search_term, search_term, search_term
              )
            end

            # Ordenar
            users_query = users_query.order("users.first_name ASC, users.last_name ASC")

            # Paginación
            paginated_users = users_query.page(params[:page]).per(params[:per_page])

            # ✅ Precargar membresías con roles
            users_with_data = paginated_users.includes(
              tenant_memberships: :role
            )

            # ✅ IMPORTANTE: Usar V1::Entities::TenantUserListEntity
            success_response(
              data: V1::Entities::TenantUserListEntity.represent(
                users_with_data,
                tenant_id: target_tenant.id
              ),
              meta: {
                current_page: paginated_users.current_page,
                total_pages: paginated_users.total_pages,
                total_count: paginated_users.total_count,
                per_page: params[:per_page]
              }
            )
          end

          # ============================================
          # VER USUARIO
          # ============================================
          desc "Get user details",
              tags: [ "Tenant - Users" ],
              success: { code: 200 }
          params do
            requires :id, type: Integer, desc: "User ID"
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            optional :include_scopes, type: Boolean, default: true, desc: "Include node and vehicle scopes"
          end
          get ":id" do
            authenticate!

            # Determinar tenant
            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Encontrar usuario
            user = ::User.kept.find(params[:id])

            # Verificar autorización
            unless current_user.platform_admin? ||
                  current_user.id == user.id ||
                  current_user.tenant_admin?(target_tenant.id) ||
                  current_user.tenant_manager?(target_tenant.id)
              api_error(message: "Access denied", status: 403)
            end

            # Verificar que el usuario tenga acceso al tenant
            unless user.has_tenant_access?(target_tenant.id)
              api_error(message: "User not found in this tenant", status: 404)
            end

            # ✅ Precargar datos relacionados
            user_with_data = ::User.kept
                                  .includes(
                                    tenant_memberships: :role
                                  )
                                  .find(user.id)

            # ✅ Responder con el USER, no con membership
            success_response(
              data: V1::Entities::TenantUserDetailEntity.represent(
                user_with_data,
                include_scopes: params[:include_scopes],
                tenant_id: target_tenant.id
              )
            )
          end

          # ============================================
          # CREAR USUARIO
          # ============================================
          desc "Create user with role and scopes",
                tags: [ "Tenant - Users" ],
                success: { code: 201 }
          params do
            optional :tenant_id, type: Integer
            requires :email, type: String
            requires :first_name, type: String
            requires :last_name, type: String
            optional :phone, type: String
            optional :password, type: String
            requires :role_slug, type: String
            optional :node_scopes, type: Array
            optional :vehicle_scopes, type: Array
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

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            result = ::Tenants::Users::CreateService.call(
              params: declared(params).except(:tenant_id),
              tenant: target_tenant,
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::TenantUserDetailEntity.represent(
                  result.data[:membership],
                  include_scopes: true,
                  tenant_id: target_tenant.id
                ),
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # ACTUALIZAR USUARIO (datos personales)
          # ============================================
          desc "Update user personal information",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :tenant_id, type: Integer
            optional :first_name, type: String
            optional :last_name, type: String
            optional :phone, type: String
            optional :avatar_url, type: String
          end
          put ":id" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            user = User.find(params[:id])

            # Solo el propio usuario, admins o managers pueden actualizar
            unless current_user.platform_admin? ||
                   current_user.id == user.id ||
                   current_user.tenant_admin?(target_tenant.id) ||
                   current_user.tenant_manager?(target_tenant.id)
              api_error(message: "Access denied", status: 403)
            end

            result = ::Tenants::Users::UpdateService.call(
              user: user,
              params: declared(params).except(:id, :tenant_id),
              current_user: current_user
            )

            if result.success?
              membership = user.tenant_memberships.find_by(tenant_id: target_tenant.id)
              success_response(
                data: Entities::TenantUserDetailEntity.represent(
                  membership,
                  include_scopes: false,
                  tenant_id: target_tenant.id
                ),
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # ELIMINAR USUARIO DEL TENANT
          # ============================================
          desc "Remove user from tenant",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :tenant_id, type: Integer
          end
          delete ":id" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            user = User.find(params[:id])
            membership = user.tenant_memberships.find_by(tenant_id: target_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            result = ::Tenants::Users::RemoveService.call(
              membership: membership,
              current_user: current_user
            )

            if result.success?
              success_response(
                data: { removed: true },
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # CAMBIAR ROL DE USUARIO
          # ============================================
          desc "Change user role in tenant",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            requires :role_slug, type: String
            optional :tenant_id, type: Integer
          end
          put ":id/role" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            user = User.find(params[:id])
            membership = user.tenant_memberships.find_by(tenant_id: target_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            result = ::Tenants::Users::ChangeRoleService.call(
              membership: membership,
              new_role_slug: params[:role_slug],
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::TenantUserDetailEntity.represent(
                  result.data[:membership],
                  include_scopes: false,
                  tenant_id: target_tenant.id
                ),
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # ACTUALIZAR SCOPES DE USUARIO
          # ============================================
          desc "Update user scopes (nodes and vehicles)",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :tenant_id, type: Integer
            optional :node_scopes, type: Array do
              requires :organizational_node_id, type: Integer
              optional :access_type, type: String, values: %w[read write admin]
              optional :include_children, type: Boolean, default: true
            end
            optional :vehicle_scopes, type: Array do
              requires :vehicle_id, type: Integer
              optional :access_type, type: String, values: %w[read write]
              optional :valid_from, type: DateTime
              optional :valid_until, type: DateTime
            end
          end
          put ":id/scopes" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id) ||
                   current_user.tenant_manager?(target_tenant.id)
              api_error(message: "Admin or Manager role required", status: 403)
            end

            user = User.find(params[:id])

            unless user.has_tenant_access?(target_tenant.id)
              api_error(message: "User not found in this tenant", status: 404)
            end

            result = ::Tenants::Users::UpdateScopesService.call(
              user: user,
              tenant: target_tenant,
              params: declared(params).except(:id, :tenant_id),
              current_user: current_user
            )

            if result.success?
              membership = user.tenant_memberships.find_by(tenant_id: target_tenant.id)
              success_response(
                data: Entities::TenantUserDetailEntity.represent(
                  membership,
                  include_scopes: true,
                  tenant_id: target_tenant.id
                ),
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # AÑADIR ROL ADICIONAL A USUARIO
          # ============================================
          desc "Add additional role to user in tenant (multi-role support)",
                tags: [ "Tenant - Users" ],
                success: { code: 201 }
          params do
            requires :id, type: Integer
            requires :role_slug, type: String
            optional :tenant_id, type: Integer
            optional :node_scopes, type: Array
            optional :vehicle_scopes, type: Array
          end
          post ":id/roles" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            user = User.find(params[:id])

            unless user.has_tenant_access?(target_tenant.id)
              api_error(message: "User not found in this tenant", status: 404)
            end

            result = ::Tenants::Users::AddRoleService.call(
              user: user,
              tenant: target_tenant,
              role_slug: params[:role_slug],
              node_scopes: params[:node_scopes],
              vehicle_scopes: params[:vehicle_scopes],
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::TenantUserDetailEntity.represent(
                  result.data[:membership],
                  include_scopes: true,
                  tenant_id: target_tenant.id
                ),
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # ELIMINAR ROL ESPECÍFICO DE USUARIO
          # ============================================
          desc "Remove specific role from user in tenant",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            requires :role_slug, type: String
            optional :tenant_id, type: Integer
          end
          delete ":id/roles/:role_slug" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            user = User.find(params[:id])
            role = Role.find_by!(slug: params[:role_slug])

            membership = user.tenant_memberships.find_by(
              tenant_id: target_tenant.id,
              role_id: role.id
            )

            unless membership
              api_error(message: "User does not have this role in tenant", status: 404)
            end

            result = ::Tenants::Users::RemoveRoleService.call(
              membership: membership,
              current_user: current_user
            )

            if result.success?
              success_response(
                data: { removed: true },
                message: result.message
              )
            else
              api_error(
                message: result.message,
                errors: result.errors,
                status: 422
              )
            end
          end

          # ============================================
          # LISTAR TODOS LOS ROLES DEL USUARIO
          # ============================================
          desc "List all roles for user in tenant",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :tenant_id, type: Integer
          end
          get ":id/roles" do
            authenticate!

            target_tenant = if current_user.platform_admin?
              params[:tenant_id] ? ::Tenant.find(params[:tenant_id]) : current_tenant
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            unless current_user.platform_admin? ||
                   current_user.tenant_admin?(target_tenant.id) ||
                   current_user.tenant_manager?(target_tenant.id)
              api_error(message: "Access denied", status: 403)
            end

            user = User.find(params[:id])
            memberships = user.tenant_memberships
                             .where(tenant_id: target_tenant.id)
                             .includes(:role)
                             .active
                             .kept

            success_response(
              data: memberships.map do |m|
                {
                  membership_id: m.id,
                  role_slug: m.role_slug,
                  role_name: m.role_name,
                  status: m.status,
                  is_primary_admin: m.is_primary_admin?,
                  is_default: m.is_default?,
                  created_at: m.created_at
                }
              end
            )
          end
        end
      end
    end
  end
end
