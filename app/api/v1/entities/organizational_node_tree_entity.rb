# app/api/v1/entities/organizational_node_tree_entity.rb
# Entity especializada para la representación en árbol de nodos organizacionales
# Usada exclusivamente para el endpoint GET /tree

module V1
  module Entities
    class OrganizationalNodeTreeEntity < Grape::Entity
      # ============================================
      # IDENTIFICACIÓN BÁSICA
      # ============================================
      expose :id, documentation: { type: "Integer", desc: "Node ID" }
      expose :name, documentation: { type: "String", desc: "Node name" }
      expose :code, documentation: { type: "String", desc: "Unique code" }
      expose :description, documentation: { type: "String", desc: "Node description" }

      # ============================================
      # JERARQUÍA
      # ============================================
      expose :parent_id, documentation: { type: "Integer", desc: "Parent node ID" }
      expose :level_id, documentation: { type: "Integer", desc: "Level ID" }
      expose :depth, documentation: { type: "Integer", desc: "Depth in tree (0=root)" }

      # ============================================
      # INFORMACIÓN DEL NIVEL
      # ============================================
      expose :level, documentation: { desc: "Level information" } do
        expose :id, documentation: { type: "Integer" }
        expose :name, documentation: { type: "String" }
        expose :order, documentation: { type: "Integer" }
        expose :allows_vehicles, documentation: { type: "Boolean" }
        expose :allows_users, documentation: { type: "Boolean" }
      end

      # ============================================
      # ESTADO DEL NODO
      # ============================================
      expose :status, documentation: { type: "String", values: %w[active inactive] }
      expose :is_active, documentation: { type: "Boolean" }
      expose :is_root, documentation: { type: "Boolean", desc: "Is root node" }
      expose :is_leaf, documentation: { type: "Boolean", desc: "Is leaf node (no children)" }

      # ============================================
      # CAPACIDADES DEL NODO
      # ============================================
      expose :can_have_children, documentation: {
        type: "Boolean",
        desc: "Can have child nodes"
      }

      expose :can_assign_vehicles, documentation: {
        type: "Boolean",
        desc: "Can have vehicles assigned"
      }

      expose :can_assign_users, documentation: {
        type: "Boolean",
        desc: "Can have users assigned"
      }

      # ============================================
      # UBICACIÓN (condicional)
      # ============================================
      expose :location, if: ->(obj, _) { obj[:location].present? },
             documentation: { desc: "Physical location information" } do
        expose :address, documentation: { type: "String" }
        expose :city, documentation: { type: "String" }
        expose :state, documentation: { type: "String" }
        expose :postal_code, documentation: { type: "String" }
        expose :country, documentation: { type: "String" }
        expose :full_address, documentation: { type: "String" }
      end

      # ============================================
      # CONTACTO (condicional)
      # ============================================
      expose :contact, if: ->(obj, _) { obj[:contact].present? },
             documentation: { desc: "Contact information" } do
        expose :phone, documentation: { type: "String" }
        expose :email, documentation: { type: "String" }
      end

      # ============================================
      # METADATA
      # ============================================
      expose :metadata, documentation: {
        type: "Hash",
        desc: "Additional metadata (JSON)"
      }

      # ============================================
      # CONTADORES
      # ============================================
      expose :counters, documentation: { desc: "Node statistics" } do
        expose :direct_children, as: :children_count, documentation: {
          type: "Integer",
          desc: "Number of direct children"
        }
        expose :total_descendants, as: :descendants_count, documentation: {
          type: "Integer",
          desc: "Total descendants (recursive)"
        }
        expose :vehicles_count, documentation: {
          type: "Integer",
          desc: "Number of vehicles assigned"
        }
      end

      # ============================================
      # PATH COMPLETO
      # ============================================
      expose :full_path, documentation: {
        type: "String",
        desc: "Full hierarchical path (e.g., 'Company / Region / Branch')"
      }

      # ============================================
      # AUDITORÍA
      # ============================================
      expose :created_at, format_with: :iso_timestamp, documentation: {
        type: "String",
        desc: "Creation timestamp"
      }

      expose :updated_at, format_with: :iso_timestamp, documentation: {
        type: "String",
        desc: "Last update timestamp"
      }

      expose :created_by, documentation: {
        type: "String",
        desc: "Email of creator"
      }

      # ============================================
      # FLAGS DE UI
      # ============================================
      expose :has_children, documentation: {
        type: "Boolean",
        desc: "Has child nodes"
      }

      expose :is_expanded, documentation: {
        type: "Boolean",
        desc: "Default expansion state for UI"
      }

      # ============================================
      # HIJOS (RECURSIVO)
      # ============================================
      expose :children, using: OrganizationalNodeTreeEntity,
             documentation: {
               type: "Array",
               is_array: true,
               desc: "Child nodes (recursive)"
             }

      # ============================================
      # FORMATTERS
      # ============================================
      format_with(:iso_timestamp) { |dt| dt&.iso8601 }
    end
  end
end
