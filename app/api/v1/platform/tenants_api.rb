# app/api/v1/platform/tenants_api.rb

module V1
  module Platform
    class TenantsApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::AuthorizationHelper

      namespace :platform do
        namespace :tenants do
          # ============================================
          # LISTAR TENANTS
          # ============================================
          desc "List all tenants (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          params do
            optional :status, type: String, values: ::Tenant::STATUSES
            optional :plan, type: String, values: ::Tenant::PLANS
            optional :search, type: String
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25, values: 1..100
          end
          get do
            require_super_admin!

            # Usar policy_scope para obtener tenants permitidos
            tenants = policy_scope(
              Tenant,
              policy_scope_class: TenantPolicy::Scope
            )

            # Filtros
            tenants = tenants.where(status: params[:status]) if params[:status]
            tenants = tenants.where(plan: params[:plan]) if params[:plan]
            tenants = tenants.search_by_name(params[:search]) if params[:search]

            # Paginación
            tenants = tenants.by_name.page(params[:page]).per(params[:per_page])

            success_response(
              data: tenants.map { |t|
                Entities::TenantEntity.represent(t, type: :summary)
              },
              meta: {
                current_page: tenants.current_page,
                total_pages: tenants.total_pages,
                total_count: tenants.total_count,
                per_page: params[:per_page]
              }
            )
          end

          # ============================================
          # VER TENANT
          # ============================================
          desc "Get tenant details (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          params do
            requires :id, type: Integer
          end
          get ":id" do
            require_super_admin!

            tenant = ::Tenant.find(params[:id])
            authorize!(tenant, :show?, policy_class: TenantPolicy)

            present tenant,
                    with: Entities::TenantEntity,
                    type: :detailed,
                    show_limits: true,
                    show_subscription: true,
                    show_timestamps: true
          end

          # ============================================
          # CREAR TENANT
          # ============================================
          desc "Create new tenant (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          params do
            requires :name, type: String
            optional :slug, type: String
            optional :domain, type: String
            optional :legal_name, type: String
            optional :tax_id, type: String
            optional :plan, type: String, values: ::Tenant::PLANS, default: "trial"
            optional :status, type: String, values: ::Tenant::STATUSES, default: "trial"
            requires :admin_email, type: String
            requires :admin_first_name, type: String
            requires :admin_last_name, type: String
            optional :admin_password, type: String
            optional :admin_phone, type: String
          end
          post do
            require_super_admin!

            # Autorizar con un tenant temporal
            temp_tenant = ::Tenant.new
            authorize!(temp_tenant, :create?, policy_class: TenantPolicy)

            result = ::Platform::Tenants::CreateService.call(
              params: declared(params),
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: {
                  tenant: Entities::TenantEntity.represent(
                    result.data[:tenant],
                    type: :detailed
                  ),
                  admin: Entities::UserEntity.represent(result.data[:admin])
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
          # ACTUALIZAR TENANT
          # ============================================
          desc "Update tenant (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          params do
            requires :id, type: Integer
            optional :name, type: String
            optional :domain, type: String
            optional :legal_name, type: String
            optional :plan, type: String, values: ::Tenant::PLANS
            optional :max_users, type: Integer
          end
          patch ":id" do
            require_super_admin!

            tenant = ::Tenant.find(params[:id])
            authorize!(tenant, :update?, policy_class: TenantPolicy)

            if tenant.update(declared(params, include_missing: false).except(:id))
              success_response(
                data: Entities::TenantEntity.represent(tenant, type: :detailed),
                message: "Tenant updated successfully"
              )
            else
              api_error(
                message: "Failed to update tenant",
                errors: tenant.errors.full_messages,
                status: 422
              )
            end
          end

          # ============================================
          # ACTIVAR TENANT
          # ============================================
          desc "Activate tenant (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          params do
            requires :id, type: Integer
          end
          post ":id/activate" do
            require_super_admin!

            tenant = ::Tenant.find(params[:id])
            authorize!(tenant, :activate?, policy_class: TenantPolicy)

            tenant.activate!

            success_response(
              data: Entities::TenantEntity.represent(tenant, type: :detailed),
              message: "Tenant activated successfully"
            )
          end

          # ============================================
          # SUSPENDER TENANT
          # ============================================
          desc "Suspend tenant (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          params do
            requires :id, type: Integer
            optional :reason, type: String
          end
          post ":id/suspend" do
            require_super_admin!

            tenant = ::Tenant.find(params[:id])
            authorize!(tenant, :suspend?, policy_class: TenantPolicy)

            tenant.suspend!(reason: params[:reason])

            success_response(
              data: Entities::TenantEntity.represent(tenant, type: :detailed),
              message: "Tenant suspended successfully"
            )
          end

          # ============================================
          # ESTADÍSTICAS GENERALES
          # ============================================
          desc "Get platform statistics (SuperAdmin only)",
                tags: [ "Platform - Tenants" ]
          get "stats/overview" do
            require_super_admin!

            stats = {
              tenants: Tenant.stats,
              users: User.stats,
              memberships: {
                platform: PlatformMembership.stats,
                tenant: {
                  total: TenantMembership.kept.count,
                  active: TenantMembership.active.count,
                  invited: TenantMembership.invited.count
                }
              }
            }

            success_response(data: stats)
          end
        end
      end
    end
  end
end
