# app/services/tenant/scopes/revoke_scope_service.rb

module Tenant
  module Scopes
    class RevokeScopeService
      include ServiceResultHelper

      attr_reader :scope, :current_user

      def initialize(scope:, current_user:)
        @scope = scope
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        ActiveRecord::Base.transaction do
          set_paper_trail_context

          scope.discard!

          success(message: "Scope revoked successfully")
        end
      rescue StandardError => e
        Rails.logger.error("[RevokeScopeService] Error: #{e.message}")
        failure(errors: "Failed to revoke scope")
      end

      private

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end
