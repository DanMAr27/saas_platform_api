# app/api/v1/entities/user_node_scope_entity.rb

module V1
  module Entities
    # Entity para scopes de nodos organizacionales

    class UserNodeScopeEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :user_id, documentation: { type: "Integer" }
      expose :organizational_node_id, documentation: { type: "Integer" }
      expose :access_type, documentation: { type: "String" }
      expose :include_children, documentation: { type: "Boolean" }

      # Información del nodo (si se solicita)
      expose :organizational_node,
             if: ->(scope, opts) { opts[:include_node] } do |scope|
        {
          id: scope.organizational_node.id,
          name: scope.organizational_node.name,
          code: scope.organizational_node.code,
          level_name: scope.organizational_node.level.name,
          full_path: scope.organizational_node.full_path
        }
      end

      # Nodos accesibles (calculado)
      expose :accessible_nodes_count,
             if: ->(scope, opts) { opts[:show_accessible_count] } do |scope|
        scope.accessible_nodes.count
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
