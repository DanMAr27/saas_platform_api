# app/services/tenant/scopes/assign_vehicle_scope_service.rb

module Tenant
  module Scopes
    class AssignVehicleScopeService
      include ServiceResultHelper

      attr_reader :user, :vehicle, :tenant, :params, :current_user

      def initialize(user:, vehicle:, tenant:, params:, current_user:)
        @user = user
        @vehicle = vehicle
        @tenant = tenant
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validaciones
        unless user.has_tenant_access?(tenant.id)
          return failure(errors: "User doesn't have access to this tenant")
        end

        unless vehicle.tenant_id == tenant.id
          return failure(errors: "Vehicle doesn't belong to this tenant")
        end

        ActiveRecord::Base.transaction do
          scope = create_or_update_scope
          return failure(errors: scope.errors.full_messages) unless scope.persisted?

          set_paper_trail_context

          success(data: scope, message: "Vehicle scope assigned successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[AssignVehicleScopeService] Error: #{e.message}")
        failure(errors: "Failed to assign vehicle scope")
      end

      private

      def create_or_update_scope
        scope = UserVehicleScope.find_or_initialize_by(
          user: user,
          vehicle: vehicle,
          tenant: tenant
        )

        scope.assign_attributes(
          access_type: params[:access_type] || "read",
          valid_from: params[:valid_from],
          valid_until: params[:valid_until],
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
