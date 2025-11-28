# app/api/v1/entities/role_entity.rb

module V1
  module Entities
    # Entity para roles

    class RoleEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :name, documentation: { type: "String" }
      expose :slug, documentation: { type: "String" }
      expose :description, documentation: { type: "String" }
      expose :context, documentation: { type: "String" }
      expose :requires_scope, documentation: { type: "Boolean" }
      expose :is_system, documentation: { type: "Boolean" }
      expose :priority, documentation: { type: "Integer" }

      # Settings (si se solicitan)
      expose :settings, if: ->(role, opts) { opts[:show_settings] }

      # Estadísticas de uso (si se solicitan)
      expose :usage_count, if: ->(role, opts) { opts[:show_usage] } do |role|
        role.usage_count
      end

      # Timestamps
      with_options(if: ->(role, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
