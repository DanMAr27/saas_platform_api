module V1
  module Management
    class TenantsApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::ManagementHelper
      helpers Helpers::AuthorizationHelper

      namespace :management do
        namespace :tenant do
          # ============================================
          # VER MI TENANT
          # ============================================
          desc "Get current tenant profile",
                tags: [ "Management - Profile" ]
          get do
            authenticate!
            require_tenant!
            verify_tenant_access!

            tenant = current_tenant
            authorize!(tenant, :show?, policy_class: ::Management::TenantPolicy)

            present tenant,
                    with: Entities::TenantEntity,
                    type: :detailed,
                    show_limits: true, # Puede ver sus límites
                    show_subscription: true # Puede ver su plan
          end

          # ============================================
          # ACTUALIZAR MI TENANT
          # ============================================
          desc "Update current tenant profile",
                tags: [ "Management - Profile" ]
          params do
            optional :name, type: String
            optional :brand_color, type: String
            optional :logo_url, type: String
            # NO permitir cambiar slug, plan, status, etc.
          end
          put do
            authenticate!
            require_tenant!
            verify_tenant_access!

            tenant = current_tenant
            authorize!(tenant, :update?, policy_class: ::Management::TenantPolicy)

            # Usar servicio específico para update seguro
            result = ::Tenants::UpdateProfileService.call(
              tenant: tenant,
              params: declared(params, include_missing: false),
              user: current_user
            )

            if result.success?
              success_response(
                data: Entities::TenantEntity.represent(result.data[:tenant], type: :detailed),
                message: "Tenant profile updated successfully"
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end
        end
      end
    end
  end
end
