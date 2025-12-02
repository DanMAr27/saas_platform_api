# app/services/tenants/organizational_nodes/move_service.rb
# Servicio para mover nodos a diferentes padres

module Tenants
  module OrganizationalNodes
    class MoveService
      include ServiceResultHelper

      attr_reader :node, :new_parent_id, :current_user

      def initialize(node:, new_parent_id:, current_user:)
        @node = node
        @new_parent_id = new_parent_id
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validaciones
        validation_result = validate_move
        return validation_result if validation_result.failure?

        # Mover
        ActiveRecord::Base.transaction do
          old_parent_id = node.parent_id

          move_node
          update_closure_table
          invalidate_cache
          set_paper_trail_context

          success(
            data: node.reload,
            message: "Node moved successfully",
            meta: {
              node_id: node.id,
              old_parent_id: old_parent_id,
              new_parent_id: new_parent_id
            }
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[MoveOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to move node: #{e.message}")
      end

      private

      def validate_move
        # Validar que el nodo esté activo
        unless node.status == "active"
          return failure(errors: "Cannot move inactive node")
        end

        # Mover a raíz (new_parent_id = nil)
        if new_parent_id.nil?
          return validate_move_to_root
        end

        # Mover a otro padre
        new_parent = OrganizationalNode.find_by(
          id: new_parent_id,
          tenant_id: node.tenant_id
        )

        unless new_parent
          return failure(errors: "New parent not found or doesn't belong to same tenant")
        end

        # Validar que el nuevo padre esté activo
        unless new_parent.status == "active"
          return failure(errors: "New parent must be active")
        end

        # Prevenir mover a sí mismo
        if new_parent.id == node.id
          return failure(errors: "Cannot move node to itself")
        end

        # Prevenir mover a un descendiente (crearía ciclo)
        if new_parent.ancestor_of?(node)
          return failure(errors: "Cannot move node to one of its descendants")
        end

        # Validar jerarquía de niveles
        expected_parent_level = node.level.level_order - 1
        unless new_parent.level.level_order == expected_parent_level
          return failure(
            errors: "New parent must be of level #{expected_parent_level}, got level #{new_parent.level.level_order}"
          )
        end

        success(data: { new_parent: new_parent })
      end

      def validate_move_to_root
        # Solo nodos de nivel 1 pueden ser raíz
        unless node.level.level_order == 1
          return failure(errors: "Only level 1 nodes can be root nodes")
        end

        success(data: { move_to_root: true })
      end

      def move_node
        node.update!(parent_id: new_parent_id)
      end

      def update_closure_table
        # El callback after_update del modelo se encarga de esto
        # pero podemos forzar recálculo si es necesario
        node.send(:update_closure_records) if node.respond_to?(:update_closure_records, true)
      end

      def invalidate_cache
        Rails.cache.delete("tenant:#{node.tenant_id}:org_tree")
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: {
            action: "move_organizational_node",
            node_id: node.id,
            new_parent_id: new_parent_id
          }
        }
      end
    end
  end
end
