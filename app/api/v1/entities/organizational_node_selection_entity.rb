# app/api/v1/entities/organizational_node_selection_entity.rb
# Entity especializada para árbol de selección de scopes de usuario
# Incluye toda la información necesaria para renderizar checkboxes con estados

module V1
  module Entities
    class OrganizationalNodeSelectionEntity < Grape::Entity
      # ============================================
      # IDENTIFICACIÓN BÁSICA
      # ============================================
      expose :id, documentation: { type: "Integer", desc: "Node ID" }
      expose :name, documentation: { type: "String", desc: "Node name" }
      expose :code, documentation: { type: "String", desc: "Node code" }
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
      expose :level, documentation: { type: "Object", desc: "Level information" } do
        expose :id, documentation: { type: "Integer" }
        expose :name, documentation: { type: "String" }
        expose :order, documentation: { type: "Integer" }
        expose :allows_vehicles, documentation: { type: "Boolean" }
        expose :allows_users, documentation: { type: "Boolean" }
      end

      # ============================================
      # PATH COMPLETO
      # ============================================
      expose :full_path, documentation: {
        type: "String",
        desc: "Full hierarchical path (e.g., 'Company / Region / Branch')"
      }

      # ============================================
      # ⭐ ESTADO DE SELECCIÓN (CRÍTICO PARA UI)
      # ============================================
      expose :selection_state, documentation: {
        type: "Object",
        desc: "Selection state information for UI rendering"
      } do
        # ¿Este nodo está guardado directamente en BD?
        expose :is_selected, documentation: {
          type: "Boolean",
          desc: "Node is directly saved in database (stored scope)"
        }

        # ¿Está cubierto por un padre seleccionado?
        expose :is_inherited, documentation: {
          type: "Boolean",
          desc: "Node is covered by a selected parent (inherited scope)"
        }

        # ¿Tiene algunos hijos seleccionados pero no todos? (estado indeterminado)
        expose :is_partial, documentation: {
          type: "Boolean",
          desc: "Node has some (but not all) children selected (indeterminate state)"
        }

        # ¿Está en el scope efectivo del usuario?
        expose :effective_coverage, documentation: {
          type: "Boolean",
          desc: "Node is within user's effective scope (selected or inherited)"
        }

        # ¿Está físicamente guardado en BD?
        expose :stored_directly, documentation: {
          type: "Boolean",
          desc: "Node ID is physically stored in user_node_scopes table"
        }

        # ID del padre que cubre este nodo (si aplica)
        expose :parent_coverage_id, documentation: {
          type: "Integer",
          desc: "ID of parent node that covers this node (if inherited)"
        }

        # Nombre del padre que cubre (para mostrar en UI)
        expose :covered_by_name, documentation: {
          type: "String",
          desc: "Name of parent node that covers this node"
        }
      end

      # ============================================
      # CAPACIDADES DEL NODO
      # ============================================
      expose :can_assign_vehicles, documentation: {
        type: "Boolean",
        desc: "Level allows vehicle assignment"
      }

      expose :can_assign_users, documentation: {
        type: "Boolean",
        desc: "Level allows user assignment"
      }

      # ============================================
      # ESTADO Y FLAGS
      # ============================================
      expose :status, documentation: {
        type: "String",
        desc: "Node status (active/inactive)"
      }

      expose :is_active, documentation: {
        type: "Boolean",
        desc: "Node is active"
      }

      expose :is_root, documentation: {
        type: "Boolean",
        desc: "Node is a root node (no parent)"
      }

      expose :is_leaf, documentation: {
        type: "Boolean",
        desc: "Node is a leaf node (no children)"
      }

      expose :has_children, documentation: {
        type: "Boolean",
        desc: "Node has child nodes"
      }

      # ============================================
      # CONTADORES (útiles para mostrar en UI)
      # ============================================
      expose :counters, documentation: {
        type: "Object",
        desc: "Various counters for UI display"
      } do
        expose :direct_children, documentation: {
          type: "Integer",
          desc: "Number of direct children"
        }

        expose :total_descendants, documentation: {
          type: "Integer",
          desc: "Total number of descendants (recursive)"
        }

        expose :vehicles_count, documentation: {
          type: "Integer",
          desc: "Number of vehicles assigned to this node"
        }

        expose :selected_descendants, documentation: {
          type: "Integer",
          desc: "Number of descendants in user's scope"
        }
      end

      # ============================================
      # HIJOS RECURSIVOS
      # ============================================
      expose :children,
             using: OrganizationalNodeSelectionEntity,
             documentation: {
               type: "Array",
               desc: "Child nodes with recursive selection state",
               is_array: true
             }

      # ============================================
      # METADATA ENTITY (para la respuesta completa)
      # ============================================
      class SelectionTreeMetadataEntity < Grape::Entity
        # Información del usuario
        expose :user_id, documentation: { type: "Integer", desc: "User ID" }

        # IDs guardados en BD (los mínimos necesarios)
        expose :stored_ids, documentation: {
          type: "Array",
          desc: "Node IDs physically stored in database",
          is_array: true
        }

        # IDs efectivos (stored + todos sus descendientes)
        expose :effective_ids, documentation: {
          type: "Array",
          desc: "All node IDs in user's scope (stored + inherited)",
          is_array: true
        }

        # IDs que deben mostrarse expandidos en la UI
        expose :expanded_ids, documentation: {
          type: "Array",
          desc: "Node IDs that should be expanded in UI",
          is_array: true
        }

        # Cobertura total
        expose :total_coverage, documentation: {
          type: "Integer",
          desc: "Total number of nodes covered by scope"
        }

        # Cantidad de nodos guardados
        expose :stored_count, documentation: {
          type: "Integer",
          desc: "Number of nodes physically stored"
        }

        # Ratio de optimización
        expose :optimization_ratio, documentation: {
          type: "Object",
          desc: "Storage optimization metrics"
        } do
          expose :stored_count, documentation: {
            type: "Integer",
            desc: "Number of stored nodes"
          }

          expose :effective_count, documentation: {
            type: "Integer",
            desc: "Number of effective nodes (after expansion)"
          }

          expose :saved_records, documentation: {
            type: "Integer",
            desc: "Number of database records saved by optimization"
          }

          expose :percentage, documentation: {
            type: "Float",
            desc: "Percentage of space saved"
          }
        end
      end
    end
  end
end
