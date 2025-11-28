# frozen_string_literal: true

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
            optional :include_scopes, type: Boolean, default: false
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

            # Obtener membresías con usuarios
            memberships = target_tenant.tenant_memberships.kept
                                      .includes(:role, :user, user: [ :user_node_scopes, :user_vehicle_scopes ])

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

            # Serializar
            success_response(
              data: memberships.map { |m|
                serialize_user_with_membership(m, include_scopes: params[:include_scopes])
              },
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

            # Obtener membresía en el tenant
            membership = user.tenant_memberships
                            .includes(:role)
                            .find_by(tenant_id: target_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            success_response(
              data: serialize_user_with_membership(
                membership,
                include_scopes: params[:include_scopes],
                detailed: true
              )
            )
          end

          # ============================================
          # CREAR USUARIO (CON ROL Y SCOPES)
          # ============================================
          desc "Create user with role and scopes",
                tags: [ "Tenant - Users" ],
                success: { code: 201 },
                detail: "Creates user, assigns role, and optionally assigns scopes in one transaction"
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"

            # Datos básicos del usuario
            requires :email, type: String
            requires :first_name, type: String
            requires :last_name, type: String
            optional :phone, type: String
            optional :password, type: String, desc: "If not provided, user will be invited"

            # Rol
            requires :role_slug, type: String,
                     values: -> { Role.tenant_roles.pluck(:slug) },
                     desc: "tenant_admin, tenant_manager, tenant_driver"

            # Scopes (opcionales según rol)
            optional :node_scopes, type: Array do
              requires :organizational_node_id, type: Integer
              optional :access_type, type: String,
                       values: UserNodeScope::ACCESS_TYPES,
                       default: "read"
              optional :include_children, type: Boolean, default: true
            end

            optional :vehicle_scopes, type: Array do
              requires :vehicle_id, type: Integer
              optional :access_type, type: String,
                       values: UserVehicleScope::ACCESS_TYPES,
                       default: "read"
              optional :valid_from, type: DateTime
              optional :valid_until, type: DateTime
            end
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
              success_response(
                data: serialize_user_with_membership(
                  result.data[:membership],
                  include_scopes: true,
                  detailed: true
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
          # ACTUALIZAR DATOS BÁSICOS
          # ============================================
          desc "Update user basic information",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :first_name, type: String
            optional :last_name, type: String
            optional :phone, type: String
            optional :avatar_url, type: String
          end
          patch ":id" do
            authenticate!
            require_tenant!
            verify_tenant_access!

            user = User.find(params[:id])

            # Autorizar
            unless current_user.platform_admin? ||
                   current_user.id == user.id ||
                   current_user.tenant_admin?(current_tenant.id)
              api_error(message: "Not authorized", status: 403)
            end

            result = ::Tenant::Users::UpdateService.call(
              user: user,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              membership = user.tenant_memberships
                              .find_by(tenant_id: current_tenant.id)

              success_response(
                data: serialize_user_with_membership(membership, detailed: true),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # CAMBIAR ROL
          # ============================================
          desc "Change user role",
                tags: [ "Tenant - Users" ],
                success: { code: 200 },
                detail: "Changes role and automatically adjusts scopes based on role requirements"
          params do
            requires :id, type: Integer
            requires :role_slug, type: String,
                     values: -> { Role.tenant_roles.pluck(:slug) }
          end
          patch ":id/role" do
            authenticate!
            require_tenant!
            verify_tenant_access!
            require_tenant_admin!

            user = User.find(params[:id])
            membership = user.tenant_memberships
                            .find_by(tenant_id: current_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            result = ::Tenant::Users::ChangeRoleService.call(
              membership: membership,
              new_role_slug: params[:role_slug],
              current_user: current_user
            )

            if result.success?
              success_response(
                data: serialize_user_with_membership(
                  result.data[:membership],
                  include_scopes: true,
                  detailed: true
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ACTUALIZAR SCOPES
          # ============================================
          desc "Update user scopes",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer

            optional :node_scopes, type: Array do
              requires :organizational_node_id, type: Integer
              optional :access_type, type: String, values: UserNodeScope::ACCESS_TYPES
              optional :include_children, type: Boolean
            end

            optional :vehicle_scopes, type: Array do
              requires :vehicle_id, type: Integer
              optional :access_type, type: String, values: UserVehicleScope::ACCESS_TYPES
              optional :valid_from, type: DateTime
              optional :valid_until, type: DateTime
            end
          end
          patch ":id/scopes" do
            authenticate!
            require_tenant!
            verify_tenant_access!
            require_tenant_admin_or_manager!

            user = User.find(params[:id])

            result = ::Tenant::Users::UpdateScopesService.call(
              user: user,
              tenant: current_tenant,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              membership = user.tenant_memberships
                              .find_by(tenant_id: current_tenant.id)

              success_response(
                data: serialize_user_with_membership(
                  membership,
                  include_scopes: true,
                  detailed: true
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # SUSPENDER USUARIO
          # ============================================
          desc "Suspend user",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
            optional :reason, type: String
          end
          post ":id/suspend" do
            authenticate!
            require_tenant!
            verify_tenant_access!
            require_tenant_admin!

            user = User.find(params[:id])
            membership = user.tenant_memberships
                            .find_by(tenant_id: current_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            # No permitir suspender al primary admin
            if membership.is_primary_admin?
              api_error(message: "Cannot suspend primary admin", status: 422)
            end

            membership.update!(status: "suspended")

            success_response(
              data: serialize_user_with_membership(membership),
              message: "User suspended successfully"
            )
          end

          # ============================================
          # REACTIVAR USUARIO
          # ============================================
          desc "Reactivate user",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
          end
          post ":id/activate" do
            authenticate!
            require_tenant!
            verify_tenant_access!
            require_tenant_admin!

            user = User.find(params[:id])
            membership = user.tenant_memberships
                            .find_by(tenant_id: current_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            membership.update!(status: "active")

            success_response(
              data: serialize_user_with_membership(membership),
              message: "User activated successfully"
            )
          end

          # ============================================
          # ELIMINAR USUARIO DEL TENANT
          # ============================================
          desc "Remove user from tenant",
                tags: [ "Tenant - Users" ],
                success: { code: 200 }
          params do
            requires :id, type: Integer
          end
          delete ":id" do
            authenticate!
            require_tenant!
            verify_tenant_access!
            require_tenant_admin!

            user = User.find(params[:id])
            membership = user.tenant_memberships
                            .find_by(tenant_id: current_tenant.id)

            unless membership
              api_error(message: "User not found in this tenant", status: 404)
            end

            # No permitir eliminar al primary admin
            if membership.is_primary_admin?
              api_error(message: "Cannot remove primary admin", status: 422)
            end

            result = ::Tenant::Users::RemoveService.call(
              membership: membership,
              current_user: current_user
            )

            if result.success?
              success_response(message: result.message)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # HELPER PRIVADO PARA SERIALIZACIÓN
          # ============================================
          helpers do
            def serialize_user_with_membership(membership, include_scopes: false, detailed: false)
              user = membership.user

              data = {
                id: user.id,
                email: user.email,
                first_name: user.first_name,
                last_name: user.last_name,
                full_name: user.full_name,
                phone: user.phone,
                avatar_url: user.avatar_url,
                email_verified: user.email_verified?,

                # Membership data
                membership: {
                  id: membership.id,
                  role_id: membership.role_id,
                  role_slug: membership.role_slug,
                  role_name: membership.role_name,
                  status: membership.status,
                  is_primary_admin: membership.is_primary_admin,
                  is_default: membership.is_default,
                  created_at: membership.created_at.iso8601
                }
              }

              if detailed
                data[:created_at] = user.created_at.iso8601
                data[:last_login_at] = user.last_login_at&.iso8601
                data[:membership][:invitation_pending] = membership.invitation_pending?
              end

              if include_scopes
                data[:scopes] = {
                  nodes: user.user_node_scopes
                            .where(tenant_id: current_tenant.id)
                            .includes(:organizational_node)
                            .map { |scope|
                              {
                                id: scope.id,
                                node_id: scope.organizational_node_id,
                                node_name: scope.organizational_node.name,
                                node_path: scope.organizational_node.full_path,
                                access_type: scope.access_type,
                                include_children: scope.include_children
                              }
                            },

                  vehicles: user.user_vehicle_scopes
                               .where(tenant_id: current_tenant.id)
                               .includes(:vehicle)
                               .map { |scope|
                                 {
                                   id: scope.id,
                                   vehicle_id: scope.vehicle_id,
                                   vehicle_name: scope.vehicle.name,
                                   license_plate: scope.vehicle.license_plate,
                                   access_type: scope.access_type,
                                   valid_from: scope.valid_from&.iso8601,
                                   valid_until: scope.valid_until&.iso8601,
                                   active: scope.active?
                                 }
                               }
                }
              end

              data
            end
          end
        end
      end
    end
  end
end
