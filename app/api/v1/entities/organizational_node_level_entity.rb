# app/api/v1/entities/organizational_node_level_entity.rb

module V1
  module Entities
    class OrganizationalNodeLevelEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :name, documentation: { type: "String" }
      expose :slug, documentation: { type: "String" }
      expose :description, documentation: { type: "String" }
      expose :level_order, documentation: { type: "Integer" }
      expose :allows_vehicles, documentation: { type: "Boolean" }
      expose :allows_users, documentation: { type: "Boolean" }
      expose :is_system, documentation: { type: "Boolean" }

      with_options(if: ->(level, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
