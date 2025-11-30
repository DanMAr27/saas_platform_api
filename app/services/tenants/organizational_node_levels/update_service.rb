# app/services/tenants/organizational_node_levels/update_service.rb
# 🆕 NUEVO ARCHIVO: Servicio para actualizar niveles organizacionales

module Tenants
  module OrganizationalNodeLevels
    class UpdateService
      include ServiceResultHelper

      attr_reader :level, :params, :current_user

      def initialize(level:, params:, current_user:)
        @level = level
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que no sea nivel del sistema si se intenta modificar configuración crítica
        if level.is_system && (params[:allows_vehicles] == false || params[:allows_users] == false)
          return failure(errors: "Cannot modify permissions on system levels")
        end

        # Validar cambio de level_order si se proporciona
        if params[:level_order].present? && params[:level_order] != level.level_order
          validation_result = validate_level_order_change
          return validation_result if validation_result.failure?
        end

        ActiveRecord::Base.transaction do
          set_paper_trail_context

          if level.update(update_params)
            success(data: level, message: "Organizational level updated successfully")
          else
            failure(errors: level.errors.full_messages)
          end
        end
      rescue StandardError => e
        Rails.logger.error("[UpdateOrganizationalLevelService] Error: #{e.message}")
        failure(errors: "Failed to update organizational level")
      end

      private

      def update_params
        allowed_params = %i[
          name slug description level_order allows_vehicles allows_users settings
        ]

        params.slice(*allowed_params).compact
      end

      def validate_level_order_change
        # Verificar que no haya otro nivel con ese order
        existing = OrganizationalNodeLevel.where(
          tenant_id: level.tenant_id,
          level_order: params[:level_order]
        ).where.not(id: level.id)

        if existing.exists?
          return failure(errors: "Level order #{params[:level_order]} is already taken")
        end

        success(data: { valid: true })
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: { performed_action: "update_organizational_level" }
        }
      end
    end
  end
end
