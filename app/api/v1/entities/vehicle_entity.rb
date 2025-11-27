# app/api/v1/entities/vehicle_entity.rb

module V1
  module Entities
    class VehicleEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :name, documentation: { type: "String" }
      expose :license_plate, documentation: { type: "String" }
      expose :fleet_number, documentation: { type: "String" }
      expose :status, documentation: { type: "String" }

      # Tipo y marca
      expose :vehicle_type, documentation: { type: "String" }
      expose :make, documentation: { type: "String" }
      expose :model, documentation: { type: "String" }
      expose :year, documentation: { type: "Integer" }

      # Nodo organizacional
      expose :organizational_node_id, documentation: { type: "Integer" }
      expose :organizational_node, using: OrganizationalNodeEntity,
             if: ->(vehicle, opts) { opts[:include_node] }

      # Detalles
      with_options(if: ->(vehicle, opts) { opts[:show_details] }) do
        expose :vin
        expose :color
        expose :fuel_type
        expose :fuel_capacity
        expose :passenger_capacity
        expose :odometer
        expose :purchase_date, format_with: :iso_timestamp
        expose :registration_expires_at, format_with: :iso_timestamp
        expose :insurance_expires_at, format_with: :iso_timestamp
        expose :last_maintenance_date, format_with: :iso_timestamp
      end

      # Estado de documentos
      with_options(if: ->(vehicle, opts) { opts[:show_status] }) do
        expose :registration_expired do |vehicle|
          vehicle.registration_expired?
        end

        expose :insurance_expired do |vehicle|
          vehicle.insurance_expired?
        end

        expose :requires_maintenance do |vehicle|
          vehicle.requires_maintenance?
        end
      end

      # Ubicación organizacional
      expose :organization_path, if: ->(vehicle, opts) { opts[:show_organization] } do |vehicle|
        vehicle.organization_path
      end

      # Timestamps
      with_options(if: ->(vehicle, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
