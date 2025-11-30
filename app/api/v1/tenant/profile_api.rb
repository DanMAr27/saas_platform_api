# app/api/v1/tenant/profile_api.rb

module V1
  module Tenant
    class ProfileApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        # ============================================
        # INFORMACIÓN DEL TENANT ACTUAL
        # ============================================
        desc "Get current tenant information",
              tags: [ "Tenant" ],
              success: { code: 200 }
        get :profile do
          authenticate!

          # Determinar el tenant a consultar
          target_tenant = if current_user.platform_admin?
            # Platform admin debe proporcionar tenant_id
            unless params[:tenant_id]
              api_error(
                message: "Platform admins must provide tenant_id parameter",
                status: 400
              )
            end

            tenant = ::Tenant.find_by(id: params[:tenant_id])
            unless tenant
              api_error(message: "Tenant not found", status: 404)
            end

            tenant
          else
            require_tenant!
            verify_tenant_access!
            current_tenant
          end

          # Autorizar con política explícita
          authorize!(target_tenant, :show?, policy_class: TenantPolicy)

          present target_tenant,
                  with: Entities::TenantEntity,
                  type: :detailed,
                  show_limits: true,
                  show_subscription: true,
                  show_timestamps: true
        end

        # ============================================
        # MEMBRESÍA DEL USUARIO ACTUAL
        # ============================================
        desc "Get current user membership in tenant",
              tags: [ "Tenant" ]
        params do
          optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
        end
        get :my_membership do
          authenticate!

          # Determinar tenant_id
          target_tenant_id = if current_user.platform_admin?
            params[:tenant_id] || api_error(
              message: "Platform admins must provide tenant_id parameter",
              status: 400
            )
          else
            require_tenant!
            current_tenant.id
          end

          membership = current_user.tenant_memberships
                                  .find_by(tenant_id: target_tenant_id, status: "active")

          unless membership
            api_error(message: "Membership not found", status: 404)
          end

          # Autorizar
          authorize!(membership, :show?, policy_class: TenantMembershipPolicy)

          present membership,
                  with: Entities::TenantMembershipEntity,
                  include_tenant: false,
                  include_user: false,
                  show_timestamps: true
        end

        # ============================================
        # USUARIOS DEL TENANT
        # ============================================
        # desc "List users in tenant",
        #       tags: [ "Tenant" ]
        # params do
        #   optional :tenant_id, type: Integer, desc: "Tenant ID (required for platform admins)"
        #   optional :status, type: String, values: TenantMembership::STATUSES
        #   optional :role_slug, type: String
        #   optional :page, type: Integer, default: 1
        #   optional :per_page, type: Integer, default: 25, values: 1..100
        # end
        # get :users do
        #   authenticate!

        #   # Determinar el tenant
        #   target_tenant = if current_user.platform_admin?
        #     unless params[:tenant_id]
        #       api_error(
        #         message: "Platform admins must provide tenant_id parameter",
        #         status: 400
        #       )
        #     end

        #     tenant = ::Tenant.find_by(id: params[:tenant_id])
        #     unless tenant
        #       api_error(message: "Tenant not found", status: 404)
        #     end

        #     tenant
        #   else
        #     unless current_tenant
        #       api_error(message: "Tenant context is required", status: 400)
        #     end

        #     unless current_user.has_tenant_access?(current_tenant.id)
        #       api_error(message: "Access denied to this tenant", status: 403)
        #     end

        #     current_tenant
        #   end

        #   # Verificar permisos (admin o manager)
        #   unless current_user.platform_admin? ||
        #          current_user.tenant_admin?(target_tenant.id) ||
        #          current_user.tenant_manager?(target_tenant.id)
        #     api_error(message: "Admin or Manager role required", status: 403)
        #   end

        #   # Usar policy_scope para obtener membresías permitidas
        #   # Como estamos filtrando por tenant específico, establecemos temporalmente el contexto
        #   memberships = if current_user.platform_admin?
        #     # Platform admins ven todas las membresías del tenant solicitado
        #     target_tenant.tenant_memberships.kept.includes(:role, :user)
        #   else
        #     # Usar policy_scope
        #     ActsAsTenant.with_tenant(target_tenant) do
        #       policy_scope(
        #         TenantMembership.kept.includes(:role, :user),
        #         policy_scope_class: TenantMembershipPolicy::Scope
        #       )
        #     end
        #   end

        #   # Filtros
        #   memberships = memberships.where(status: params[:status]) if params[:status]

        #   if params[:role_slug]
        #     role = Role.tenant_roles.find_by(slug: params[:role_slug])
        #     memberships = memberships.where(role_id: role.id) if role
        #   end

        #   # Paginación
        #   memberships = memberships.page(params[:page]).per(params[:per_page])

        #   success_response(
        #     data: memberships.map { |m|
        #       Entities::TenantMembershipEntity.represent(
        #         m,
        #         include_user: true,
        #         include_tenant: false
        #       )
        #     },
        #     meta: {
        #       current_page: memberships.current_page,
        #       total_pages: memberships.total_pages,
        #       total_count: memberships.total_count,
        #       per_page: params[:per_page],
        #       tenant_id: target_tenant.id,
        #       tenant_name: target_tenant.name
        #     }
        #   )
        # end

        # ============================================
        # INVITAR USUARIO
        # ============================================
        desc "Invite user to tenant",
              tags: [ "Tenant" ]
        params do
          optional :tenant_id, type: Integer
          requires :email, type: String
          requires :first_name, type: String
          requires :last_name, type: String
          requires :role_slug, type: String
          optional :phone, type: String
        end
        post :invite do
          authenticate!

          # Determinar el tenant
          target_tenant = if current_user.platform_admin?
            unless params[:tenant_id]
              api_error(
                message: "Platform admins must provide tenant_id parameter",
                status: 400
              )
            end

            ::Tenant.find(params[:tenant_id])
          else
            require_tenant!
            verify_tenant_access!
            current_tenant
          end

          # Verificar permisos
          unless current_user.platform_admin? ||
                 current_user.tenant_admin?(target_tenant.id) ||
                 current_user.tenant_manager?(target_tenant.id)
            api_error(message: "Admin or Manager role required", status: 403)
          end

          # Crear membresía temporal para autorización
          temp_membership = TenantMembership.new(tenant: target_tenant)
          authorize!(temp_membership, :create?, policy_class: TenantMembershipPolicy)

          result = Platform::Tenants::InviteService.call(
            tenant: target_tenant,
            params: declared(params).except(:tenant_id),
            invited_by: current_user
          )

          if result.success?
            status 201
            success_response(
              data: {
                user: Entities::UserEntity.represent(result.data[:user]),
                membership: Entities::TenantMembershipEntity.represent(
                  result.data[:membership],
                  include_user: false,
                  include_tenant: false
                ),
                invitation_token: result.data[:invitation_token]
              },
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
        # ESTADÍSTICAS DEL TENANT
        # ============================================
        desc "Get tenant statistics",
              tags: [ "Tenant" ]
        params do
          optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
        end
        get :stats do
          authenticate!

          # Determinar el tenant
          target_tenant = if current_user.platform_admin?
            unless params[:tenant_id]
              api_error(
                message: "Platform admins must provide tenant_id parameter",
                status: 400
              )
            end

            tenant = ::Tenant.find_by(id: params[:tenant_id])
            unless tenant
              api_error(message: "Tenant not found", status: 404)
            end

            tenant
          else
            require_tenant!
            unless current_user.tenant_admin?(current_tenant.id)
              api_error(message: "Admin role required", status: 403)
            end
            current_tenant
          end

          stats = {
            users: {
              total: target_tenant.tenant_memberships.count,
              active: target_tenant.active_memberships.count,
              invited: target_tenant.tenant_memberships.invited.count,
              suspended: target_tenant.tenant_memberships.suspended.count
            },
            roles: TenantMembership.role_distribution_for_tenant(target_tenant.id),
            limits: {
              max_users: target_tenant.max_users,
              current_users: target_tenant.active_users.count,
              remaining_slots: target_tenant.remaining_user_slots,
              limit_reached: target_tenant.user_limit_reached?
            },
            subscription: {
              status: target_tenant.status,
              plan: target_tenant.plan,
              trial_days_remaining: target_tenant.trial? ? target_tenant.trial_days_remaining : nil
            }
          }

          success_response(data: stats)
        end
      end
    end
  end
end
