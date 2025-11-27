# app/services/tenant/organizational_nodes/update_service.rb

module Tenants
  module OrganizationalNodes
    class UpdateService
      include ServiceResultHelper

      attr_reader :node, :params, :current_user

      def initialize(node:, params:, current_user:)
        @node = node
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        ActiveRecord::Base.transaction do
          set_paper_trail_context

          if node.update(update_params)
            success(data: node, message: "Organizational node updated successfully")
          else
            failure(errors: node.errors.full_messages)
          end
        end
      rescue StandardError => e
        Rails.logger.error("[UpdateOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to update organizational node")
      end

      private

      def update_params
        allowed_params = %i[
          name code description address city state postal_code country
          phone email status metadata
        ]

        params.slice(*allowed_params).compact
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end
