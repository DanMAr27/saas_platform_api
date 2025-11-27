# app/services/tenant/scopes/assign_node_scope_service.rb

module Tenant
  module Scopes
    class AssignNodeScopeService
      include ServiceResultHelper

      attr_reader :user, :node, :tenant, :params, :current_user

      def initialize(user:, node:, tenant:, params:, current_user:)
        @user = user
        @node = node
        @tenant = tenant
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que el usuario pertenezca al tenant
        unless user.has_tenant_access?(tenant.id)
          return failure(errors: "User doesn't have access to this tenant")
        end

        # Validar que el nodo pertenezca al tenant
        unless node.tenant_id == tenant.id
          return failure(errors: "Node doesn't belong to this tenant")
        end

        ActiveRecord::Base.transaction do
          scope = create_or_update_scope
          return failure(errors: scope.errors.full_messages) unless scope.persisted?

          set_paper_trail_context

          success(data: scope, message: "Node scope assigned successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[AssignNodeScopeService] Error: #{e.message}")
        failure(errors: "Failed to assign node scope")
      end

      private

      def create_or_update_scope
        scope = UserNodeScope.find_or_initialize_by(
          user: user,
          organizational_node: node,
          tenant: tenant
        )

        scope.assign_attributes(
          access_type: params[:access_type] || "read",
          include_children: params[:include_children].nil? ? true : params[:include_children],
          created_by: current_user&.id
        )

        scope.save!
        scope
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end
