# app/api/v1/entities/user_vehicle_scope_entity.rb

module V1
  module Entities
    class UserVehicleScopeEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :user_id, documentation: { type: "Integer" }
      expose :vehicle_id, documentation: { type: "Integer" }
      expose :access_type, documentation: { type: "String" }
      expose :valid_from, format_with: :iso_timestamp
      expose :valid_until, format_with: :iso_timestamp

      expose :active do |scope|
        scope.active?
      end

      expose :user, using: UserEntity, if: ->(scope, opts) { opts[:include_user] }
      expose :vehicle, using: VehicleEntity, if: ->(scope, opts) { opts[:include_vehicle] }

      with_options(if: ->(scope, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
