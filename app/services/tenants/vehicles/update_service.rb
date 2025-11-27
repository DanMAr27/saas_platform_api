# app/services/tenant/vehicles/update_service.rb

module Tenants
  module Vehicles
    class UpdateService
      include ServiceResultHelper

      attr_reader :vehicle, :params, :current_user

      def initialize(vehicle:, params:, current_user:)
        @vehicle = vehicle
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        ActiveRecord::Base.transaction do
          set_paper_trail_context

          if vehicle.update(update_params)
            success(data: vehicle, message: "Vehicle updated successfully")
          else
            failure(errors: vehicle.errors.full_messages)
          end
        end
      rescue StandardError => e
        Rails.logger.error("[UpdateVehicleService] Error: #{e.message}")
        failure(errors: "Failed to update vehicle")
      end

      private

      def update_params
        allowed_params = %i[
          name organizational_node_id vehicle_type make model year status
          color fuel_type fuel_capacity passenger_capacity purchase_date
          registration_expires_at insurance_expires_at last_maintenance_date
          odometer metadata specifications
        ]

        params.slice(*allowed_params).compact
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end
