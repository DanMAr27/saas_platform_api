# app/services/tenant/organizational_nodes/move_service.rb

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
        # Validar nuevo padre
        validation_result = validate_move
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          set_paper_trail_context

          new_parent = new_parent_id ? OrganizationalNode.find(new_parent_id) : nil

          if node.move_to(new_parent)
            success(data: node.reload, message: "Node moved successfully")
          else
            failure(errors: node.errors.full_messages)
          end
        end
      rescue ActiveRecord::RecordNotFound
        failure(errors: "Parent node not found")
      rescue StandardError => e
        Rails.logger.error("[MoveOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to move node")
      end

      private

      def validate_move
        # Si no hay nuevo padre, mover a raíz (válido)
        return success(data: { valid: true }) if new_parent_id.nil?

        new_parent = OrganizationalNode.find_by(id: new_parent_id, tenant_id: node.tenant_id)

        unless new_parent
          return failure(errors: "Parent node not found or doesn't belong to same tenant")
        end

        # No puede moverse a sí mismo
        if new_parent.id == node.id
          return failure(errors: "Cannot move node to itself")
        end

        # No puede moverse a uno de sus descendientes
        if new_parent.descendant_of?(node)
          return failure(errors: "Cannot move node to its own descendant")
        end

        # Validar niveles
        if new_parent.level.level_order >= node.level.level_order
          return failure(errors: "Parent node must be of a higher level")
        end

        success(data: { valid: true })
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: {
            performed_action: "move_organizational_node",
            old_parent_id: node.parent_id,
            new_parent_id: new_parent_id
          }
        }
      end
    end
  end
end
