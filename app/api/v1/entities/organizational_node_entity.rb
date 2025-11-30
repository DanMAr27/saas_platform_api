# app/api/entities/organizational_node_entity.rb
# Entity para serializar nodos organizacionales en la API

module Entities
  class OrganizationalNodeEntity < Grape::Entity
    # ============================================
    # CAMPOS BÁSICOS
    # ============================================
    expose :id
    expose :name
    expose :code
    expose :description, if: ->(obj, opts) { opts[:show_details] }
    expose :status

    # ============================================
    # 🆕 NUEVO: PATH COMPLETO
    # ============================================
    # Estos campos son clave para tu caso de uso de dropdowns

    # Path formateado: "CarfastCliente / Sucursal 1 / Departamento1"
    expose :full_path, if: ->(obj, opts) { opts[:include_path] } do |node|
      node.full_path
    end

    # Array de nombres: ["CarfastCliente", "Sucursal 1", "Departamento1"]
    expose :path_array, if: ->(obj, opts) { opts[:include_path] } do |node|
      node.path_array
    end

    # Array de IDs: [1, 5, 12] - útil para reconstruir la selección
    expose :path_ids, if: ->(obj, opts) { opts[:include_path] } do |node|
      node.path_ids
    end

    # ============================================
    # RELACIONES JERÁRQUICAS
    # ============================================
    expose :parent_id
    expose :level_id

    # Profundidad en el árbol (0 = raíz)
    expose :depth, if: ->(obj, opts) { opts[:show_hierarchy] } do |node|
      node.depth
    end

    # ============================================
    # NIVEL ORGANIZACIONAL
    # ============================================
    expose :level, if: ->(obj, opts) { opts[:include_level] }, using: OrganizationalNodeLevelEntity

    # ============================================
    # 🆕 NUEVO: INFORMACIÓN DEL PADRE
    # ============================================
    expose :parent, if: ->(obj, opts) { opts[:show_hierarchy] && obj.parent.present? } do |node|
      {
        id: node.parent.id,
        name: node.parent.name,
        level_name: node.parent.level.name
      }
    end

    # ============================================
    # 🆕 NUEVO: CAPACIDADES DEL NODO
    # ============================================
    # Indica si este nodo puede tener vehículos/usuarios asignados
    expose :can_assign_vehicles do |node|
      node.level&.allows_vehicles || false
    end

    expose :can_assign_users do |node|
      node.level&.allows_users || false
    end

    # ============================================
    # ESTADO DEL NODO
    # ============================================
    expose :is_root do |node|
      node.root?
    end

    expose :is_leaf do |node|
      node.leaf?
    end

    # ============================================
    # CONTADORES
    # ============================================
    expose :children_count, if: ->(obj, opts) { opts[:show_details] } do |node|
      node.children.count
    end

    expose :descendants_count, if: ->(obj, opts) { opts[:show_details] } do |node|
      node.descendants.count
    end

    # ============================================
    # UBICACIÓN FÍSICA
    # ============================================
    expose :address, if: ->(obj, opts) { opts[:show_details] }
    expose :city, if: ->(obj, opts) { opts[:show_details] }
    expose :state, if: ->(obj, opts) { opts[:show_details] }
    expose :postal_code, if: ->(obj, opts) { opts[:show_details] }
    expose :country, if: ->(obj, opts) { opts[:show_details] }

    # ============================================
    # CONTACTO
    # ============================================
    expose :phone, if: ->(obj, opts) { opts[:show_details] }
    expose :email, if: ->(obj, opts) { opts[:show_details] }

    # ============================================
    # VISTA DE ÁRBOL
    # ============================================
    # Los hijos se incluyen recursivamente cuando tree_view=true
    expose :children, if: ->(obj, opts) { opts[:tree_view] } do |node, opts|
      OrganizationalNodeEntity.represent(
        node.children.active.includes(:level),
        opts.merge(tree_view: true, include_level: true)
      )
    end

    # ============================================
    # TIMESTAMPS
    # ============================================
    expose :created_at, if: ->(obj, opts) { opts[:show_timestamps] }
    expose :updated_at, if: ->(obj, opts) { opts[:show_timestamps] }
  end
end
