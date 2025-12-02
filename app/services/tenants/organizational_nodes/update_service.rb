# app/services/tenants/organizational_nodes/update_service.rb
# Servicio para actualizar nodos organizacionales

module Tenants
  module OrganizationalNodes
    class UpdateService
      include ServiceResultHelper

      attr_reader :node, :params, :current_user

      def initialize(node:, params:, current_user:)
        @node = node
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validaciones
        validation_result = validate_params
        return validation_result if validation_result.failure?

        # Actualizar
        ActiveRecord::Base.transaction do
          update_node
          invalidate_cache
          set_paper_trail_context

          success(
            data: node.reload,
            message: "Organizational node updated successfully",
            meta: { node_id: node.id }
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[UpdateOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to update organizational node: #{e.message}")
      end

      private

      def validate_params
        # Validar código único si cambió
        if params[:code].present? && params[:code] != node.code
          existing = OrganizationalNode.where(
            tenant_id: node.tenant_id,
            code: params[:code]
          ).where.not(id: node.id, deleted_at: nil).exists?

          if existing
            return failure(errors: "Code already exists in this tenant")
          end
        end

        # No permitir cambio de nivel si tiene hijos
        if params[:level_id].present? && params[:level_id] != node.level_id
          if node.children.any?
            return failure(errors: "Cannot change level of node with children")
          end
        end

        # No permitir inactivar si tiene hijos activos
        if params[:status] == "inactive" && node.status == "active"
          if node.children.active.any?
            return failure(errors: "Cannot inactivate node with active children")
          end
        end

        # No permitir inactivar si tiene vehículos asignados
        if params[:status] == "inactive" && node.vehicles.any?
          return failure(errors: "Cannot inactivate node with assigned vehicles")
        end

        success(data: { valid: true })
      end

      def update_node
        update_params = build_update_params
        node.update!(update_params)
      end

      def build_update_params
        allowed_params = %i[
          name code description
          address city state postal_code country
          phone email
          status metadata
        ]

        params.slice(*allowed_params).compact
      end

      def invalidate_cache
        Rails.cache.delete("tenant:#{node.tenant_id}:org_tree")
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: {
            action: "update_organizational_node",
            node_id: node.id
          }
        }
      end
    end
  end
end
