# app/api/v1/entities/organizational_node_entity.rb

module V1
  module Entities
    class OrganizationalNodeEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :name, documentation: { type: "String" }
      expose :code, documentation: { type: "String" }
      expose :description, documentation: { type: "String" }
      expose :status, documentation: { type: "String" }

      # Relaciones
      expose :level_id, documentation: { type: "Integer" }
      expose :parent_id, documentation: { type: "Integer" }

      expose :level, using: OrganizationalNodeLevelEntity,
             if: ->(node, opts) { opts[:include_level] }

      # Ubicación
      with_options(if: ->(node, opts) { opts[:show_details] }) do
        expose :address
        expose :city
        expose :state
        expose :postal_code
        expose :country
        expose :phone
        expose :email
      end

      # Jerarquía
      with_options(if: ->(node, opts) { opts[:show_hierarchy] }) do
        expose :depth do |node|
          node.depth
        end

        expose :full_path do |node|
          node.full_path
        end

        expose :has_children do |node|
          !node.leaf?
        end

        expose :children_count do |node|
          node.children.count
        end
      end

      # Timestamps
      with_options(if: ->(node, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end

      # Vista de árbol - CORREGIDO
      with_options(if: ->(node, opts) { opts[:tree_view] == true }) do
        expose :level, using: OrganizationalNodeLevelEntity
        expose :children, using: OrganizationalNodeEntity do |node, opts|
          node.children.map { |child| OrganizationalNodeEntity.represent(child, opts.merge(tree_view: true)) }
        end
      end
    end
  end
end
