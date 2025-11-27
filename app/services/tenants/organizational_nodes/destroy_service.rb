# app/services/tenant/organizational_nodes/destroy_service.rb

module Tenants
  module OrganizationalNodes
    class DestroyService
      include ServiceResultHelper

      attr_reader :node, :current_user

      def initialize(node:, current_user:)
        @node = node
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que no tenga hijos
        if node.children.exists?
          return failure(errors: "Cannot delete node with children. Move or delete children first.")
        end

        ActiveRecord::Base.transaction do
          set_paper_trail_context

          node.discard!

          success(message: "Organizational node deleted successfully")
        end
      rescue StandardError => e
        Rails.logger.error("[DestroyOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to delete organizational node")
      end

      private

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: { performed_action: "destroy_organizational_node" }
        }
      end
    end
  end
end
