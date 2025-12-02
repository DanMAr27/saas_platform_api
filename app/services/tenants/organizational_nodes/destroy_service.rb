# app/services/tenants/organizational_nodes/destroy_service.rb
# Servicio para eliminar (soft delete) nodos

module Tenants
  module OrganizationalNodes
    class DestroyService
      include ServiceResultHelper

      attr_reader :node, :current_user

      def initialize(node:, current_user:)
        @node = node
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validaciones
        validation_result = validate_destroy
        return validation_result if validation_result.failure?

        # Eliminar (soft delete)
        ActiveRecord::Base.transaction do
          destroy_node
          invalidate_cache
          set_paper_trail_context

          success(
            message: "Organizational node deleted successfully",
            meta: { node_id: node.id }
          )
        end
      rescue StandardError => e
        Rails.logger.error("[DestroyOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to delete node: #{e.message}")
      end

      private

      def validate_destroy
        # No permitir eliminar si tiene hijos
        if node.children.exists?
          return failure(
            errors: "Cannot delete node with children. Delete or move children first.",
            meta: { children_count: node.children.count }
          )
        end

        # No permitir eliminar si tiene vehículos asignados
        if node.vehicles.exists?
          return failure(
            errors: "Cannot delete node with assigned vehicles. Reassign vehicles first.",
            meta: { vehicles_count: node.vehicles.count }
          )
        end

        # TODO: Validar scopes de usuarios cuando esté implementado
        # if UserNodeScope.where(organizational_node_id: node.id).exists?
        #   return failure(errors: "Cannot delete node assigned to users")
        # end

        success(data: { can_destroy: true })
      end

      def destroy_node
        node.update!(
          deleted_at: Time.current,
          deleted_by: current_user&.id,
          status: "inactive"
        )
      end

      def invalidate_cache
        Rails.cache.delete("tenant:#{node.tenant_id}:org_tree")
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: {
            action: "destroy_organizational_node",
            node_id: node.id
          }
        }
      end
    end
  end
end
