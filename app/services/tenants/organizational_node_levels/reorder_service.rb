# app/services/tenants/organizational_node_levels/reorder_service.rb
# 🆕 NUEVO ARCHIVO: Servicio para reordenar niveles organizacionales
# Permite actualizar el orden jerárquico de múltiples niveles de una vez

module Tenants
  module OrganizationalNodeLevels
    class ReorderService
      include ServiceResultHelper

      attr_reader :levels_data, :tenant, :current_user

      def initialize(levels_data:, tenant:, current_user:)
        @levels_data = levels_data
        @tenant = tenant
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar datos
        validation_result = validate_levels_data
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          set_paper_trail_context

          updated_levels = []

          levels_data.each do |level_data|
            level = OrganizationalNodeLevel.find(level_data[:id])

            # Verificar que pertenece al tenant
            unless level.tenant_id == tenant.id
              return failure(errors: "Level #{level.id} does not belong to this tenant")
            end

            # No se pueden reordenar niveles del sistema
            if level.is_system
              return failure(errors: "Cannot reorder system level: #{level.name}")
            end

            # Actualizar el order
            if level.update(level_order: level_data[:level_order])
              updated_levels << level
            else
              return failure(errors: level.errors.full_messages)
            end
          end

          success(
            data: updated_levels.sort_by(&:level_order),
            message: "Levels reordered successfully"
          )
        end
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Level not found: #{e.message}")
      rescue StandardError => e
        Rails.logger.error("[ReorderOrganizationalLevelsService] Error: #{e.message}")
        failure(errors: "Failed to reorder levels")
      end

      private

      def validate_levels_data
        # Verificar que no haya IDs duplicados
        level_ids = levels_data.map { |l| l[:id] }
        if level_ids.uniq.size != level_ids.size
          return failure(errors: "Duplicate level IDs provided")
        end

        # Verificar que no haya orders duplicados
        orders = levels_data.map { |l| l[:level_order] }
        if orders.uniq.size != orders.size
          return failure(errors: "Duplicate level orders provided")
        end

        # Verificar que los orders sean consecutivos (opcional)
        sorted_orders = orders.sort
        expected_orders = (sorted_orders.first..sorted_orders.last).to_a
        unless sorted_orders == expected_orders
          return failure(errors: "Level orders must be consecutive")
        end

        success(data: { valid: true })
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: {
            performed_action: "reorder_organizational_levels",
            levels_count: levels_data.size
          }
        }
      end
    end
  end
end
