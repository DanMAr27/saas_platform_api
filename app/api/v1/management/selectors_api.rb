# app/api/v1/management/selectors_api.rb

module V1
  module Management
    class SelectorsApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::ManagementHelper
      helpers Helpers::AuthorizationHelper

      namespace :management do
        namespace :selectors do
          # ============================================
          # ORGANIZATIONAL NODES SELECTORS
          # ============================================
          desc "Get organizational nodes for selectors/dropdowns",
               tags: [ "Management - Selectors" ],
               success: { code: 200 },
               detail: "Returns an optimized, flat list of active organizational nodes for UI selectors. The payload contains the full path for easier hierarchical display without the heavy nesting."
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (required for platform admins)"
            optional :grouped, type: Boolean, default: false, desc: "Group options by root node"
          end
          get "organizational_nodes" do
            authenticate!

            # Resolve tenant
            target_tenant = if current_user.platform_admin? && platform_context?
                              unless params[:tenant_id]
                                api_error(message: "Platform admins must provide tenant_id", status: 400)
                              end
                              ::Tenant.find_by(id: params[:tenant_id]) || api_error(message: "Tenant not found", status: 404)
            else
                              require_tenant!
                              verify_tenant_access!
                              current_tenant
            end

            # Base scope for active nodes in the tenant
            nodes = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                OrganizationalNode.includes(:level, :parent),
                policy_scope_class: OrganizationalNodePolicy::Scope
              )
            end

            query = OrganizationalNodesQuery.new(nodes)

            options = if params[:grouped]
              query.grouped_dropdown_options
            else
              query.dropdown_options
            end

            success_response(
              data: options,
              meta: {
                total_options: options.is_a?(Array) ? options.count : options.sum { |g| g[:options].count },
                grouped: params[:grouped].present?
              }
            )
          end
        end
      end
    end
  end
end
