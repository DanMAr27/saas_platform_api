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

            # Obtener membresías
            memberships = target_tenant.tenant_memberships.kept
                                      .includes(:role, :user)

            # Filtros
            memberships = memberships.where(status: params[:status]) if params[:status]

            if params[:role_slug]
              memberships = memberships.joins(:role)
                                      .where(roles: { slug: params[:role_slug] })
            end

            if params[:search]
              search_term = "%#{params[:search].downcase}%"
              memberships = memberships.joins(:user)
                                      .where("LOWER(users.email) LIKE ? OR
                                              LOWER(users.first_name) LIKE ? OR
                                              LOWER(users.last_name) LIKE ?",
                                            search_term, search_term, search_term)
            end

            # Paginación
            memberships = memberships.page(params[:page]).per(params[:per_page])

            # ✅ USAR TenantUserListEntity para el listado
            success_response(
              data: Entities::TenantUserListEntity.represent(
                memberships,
                tenant_id: target_tenant.id
              ),
              meta: {
                current_page: memberships.current_page,
                total_pages: memberships.total_pages,
                total_count: memberships.total_count,
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
            requires :id, type: Integer
            optional :tenant_id, type: Integer
            optional :include_scopes, type: Boolean, default: true
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

            user = User.find(params[:id])

            # Autorizar
            unless current_user.platform_admin? ||
                   current_user.id == user.id ||
                   current_user.tenant_admin?(target_tenant.id) ||
                   current_user.tenant_manager?(target_tenant.id)
              api_error(message: "Access denied", status: 403)
            end

            # Obtener membresía
            membership = user.tenant_memberships
                            .includes(:role)
                            .find_by(tenant_id: target_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            # ✅ USAR TenantUserDetailEntity para el detalle
            success_response(
              data: Entities::TenantUserDetailEntity.represent(
                membership,
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
                   current_user.tenant_admin?(target_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end

            result = ::Tenant::Users::CreateService.call(
              params: declared(params).except(:tenant_id),
              tenant: target_tenant,
              current_user: current_user
            )

            if result.success?
              status 201
              # ✅ USAR TenantUserDetailEntity para la respuesta
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
        end
      end
    end
  end
end
