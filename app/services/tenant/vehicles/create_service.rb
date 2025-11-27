# app/services/tenant/vehicles/create_service.rb

module Tenant
  module Vehicles
    class CreateService
      include ServiceResultHelper

      attr_reader :params, :tenant, :current_user

      def initialize(params:, tenant:, current_user:)
        @params = params
        @tenant = tenant
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        validation_result = validate_params
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          vehicle = create_vehicle
          return failure(errors: vehicle.errors.full_messages) unless vehicle.persisted?

          set_paper_trail_context

          success(data: vehicle, message: "Vehicle created successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[CreateVehicleService] Error: #{e.message}")
        failure(errors: "Failed to create vehicle")
      end

      private

      def validate_params
        required_fields = %i[name license_plate]
        missing_fields = required_fields.select { |f| params[f].blank? }

        if missing_fields.any?
          return failure(errors: "Missing required fields: #{missing_fields.join(', ')}")
        end

        # Validar nodo organizacional si se proporciona
        if params[:organizational_node_id]
          node = OrganizationalNode.find_by(id: params[:organizational_node_id], tenant_id: tenant.id)
          unless node
            return failure(errors: "Organizational node not found or doesn't belong to tenant")
          end
        end

        success(data: { valid: true })
      end

      def create_vehicle
        vehicle_params = {
          tenant: tenant,
          name: params[:name],
          license_plate: params[:license_plate],
          vin: params[:vin],
          fleet_number: params[:fleet_number],
          vehicle_type: params[:vehicle_type],
          make: params[:make],
          model: params[:model],
          year: params[:year],
          status: params[:status] || "active",
          color: params[:color],
          fuel_type: params[:fuel_type],
          fuel_capacity: params[:fuel_capacity],
          passenger_capacity: params[:passenger_capacity],
          organizational_node_id: params[:organizational_node_id],
          purchase_date: params[:purchase_date],
          registration_expires_at: params[:registration_expires_at],
          insurance_expires_at: params[:insurance_expires_at],
          odometer: params[:odometer],
          metadata: params[:metadata] || {},
          specifications: params[:specifications] || {},
          created_by: current_user&.id
        }

        Vehicle.create!(vehicle_params.compact)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: { performed_action: "create_vehicle" }
        }
      end
    end
  end
end
