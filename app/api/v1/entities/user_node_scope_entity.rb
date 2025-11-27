# app/api/v1/entities/user_node_scope_entity.rb

module V1
  module Entities
    class UserNodeScopeEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :user_id, documentation: { type: "Integer" }
      expose :organizational_node_id, documentation: { type: "Integer" }
      expose :access_type, documentation: { type: "String" }
      expose :include_children, documentation: { type: "Boolean" }

      expose :user, using: UserEntity, if: ->(scope, opts) { opts[:include_user] }
      expose :organizational_node, using: OrganizationalNodeEntity,
             if: ->(scope, opts) { opts[:include_node] }

      with_options(if: ->(scope, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
