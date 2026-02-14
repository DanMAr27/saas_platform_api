# app/api/v1/management/profile_api.rb

module V1
  module Management
    class ProfileApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::ManagementHelper
      helpers Helpers::AuthorizationHelper

      namespace :management do
        # ============================================
        # INFORMACIÓN DEL TENANT ACTUAL
        # ============================================
        desc "Get current tenant information",
              tags: [ "Management - Profile" ],
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
              tags: [ "Management - Profile" ]
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
        # INVITAR USUARIO
        # ============================================
        desc "Invite user to tenant",
              tags: [ "Management - Profile" ]
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
              tags: [ "Management - Profile" ]
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
