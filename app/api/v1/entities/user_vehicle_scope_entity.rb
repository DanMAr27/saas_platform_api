# app/api/v1/entities/user_vehicle_scope_entity.rb

module V1
  module Entities
    # Entity para scopes de vehículos

    class UserVehicleScopeEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :user_id, documentation: { type: "Integer" }
      expose :vehicle_id, documentation: { type: "Integer" }
      expose :access_type, documentation: { type: "String" }
      expose :valid_from, format_with: :iso_timestamp
      expose :valid_until, format_with: :iso_timestamp

      # Estado del scope
      expose :active do |scope|
        scope.active?
      end

      expose :expired do |scope|
        scope.expired?
      end

      # Información del vehículo (si se solicita)
      expose :vehicle,
             if: ->(scope, opts) { opts[:include_vehicle] } do |scope|
        {
          id: scope.vehicle.id,
          name: scope.vehicle.name,
          license_plate: scope.vehicle.license_plate,
          fleet_number: scope.vehicle.fleet_number,
          vehicle_type: scope.vehicle.vehicle_type,
          status: scope.vehicle.status
        }
      end

      # Usuario (opcional)
      expose :user, using: UserEntity,
             if: ->(scope, opts) { opts[:include_user] }

      # Timestamps
      with_options(if: ->(scope, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
