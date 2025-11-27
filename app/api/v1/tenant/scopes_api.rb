# app/api/v1/tenant/scopes_api.rb

module V1
  module Tenant
    class ScopesApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :scopes do
          # ============================================
          # ASIGNAR SCOPE DE NODO
          # ============================================
          desc "Assign node scope to user",
                tags: [ "Tenant - Scopes" ]
          params do
            optional :tenant_id, type: Integer
            requires :user_id, type: Integer
            requires :node_id, type: Integer
            optional :access_type, type: String, values: UserNodeScope::ACCESS_TYPES, default: "read"
            optional :include_children, type: Boolean, default: true
          end
          post :nodes do
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

            user = User.find(params[:user_id])
            node = OrganizationalNode.find(params[:node_id])

            # Autorizar
            require_tenant_admin_or_manager!

            result = ::Tenant::Scopes::AssignNodeScopeService.call(
              user: user,
              node: node,
              tenant: target_tenant,
              params: declared(params),
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::UserNodeScopeEntity.represent(result.data),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ASIGNAR SCOPE DE VEHÍCULO
          # ============================================
          desc "Assign vehicle scope to user",
                tags: [ "Tenant - Scopes" ]
          params do
            optional :tenant_id, type: Integer
            requires :user_id, type: Integer
            requires :vehicle_id, type: Integer
            optional :access_type, type: String, values: UserVehicleScope::ACCESS_TYPES, default: "read"
            optional :valid_from, type: DateTime
            optional :valid_until, type: DateTime
          end
          post :vehicles do
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

            user = User.find(params[:user_id])
            vehicle = Vehicle.find(params[:vehicle_id])

            # Autorizar
            require_tenant_admin_or_manager!

            result = ::Tenant::Scopes::AssignVehicleScopeService.call(
              user: user,
              vehicle: vehicle,
              tenant: target_tenant,
              params: declared(params),
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::UserVehicleScopeEntity.represent(result.data),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # REVOCAR SCOPE
          # ============================================
          desc "Revoke scope",
                tags: [ "Tenant - Scopes" ]
          params do
            requires :type, type: String, values: %w[node vehicle]
            requires :id, type: Integer
          end
          delete ":type/:id" do
            authenticate!
            require_tenant_admin_or_manager!

            scope = case params[:type]
            when "node"
                      UserNodeScope.find(params[:id])
            when "vehicle"
                      UserVehicleScope.find(params[:id])
            end

            result = ::Tenant::Scopes::RevokeScopeService.call(
              scope: scope,
              current_user: current_user
            )

            if result.success?
              success_response(message: result.message)
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end
        end
      end
    end
  end
end
