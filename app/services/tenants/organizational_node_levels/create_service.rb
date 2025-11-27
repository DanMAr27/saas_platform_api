# app/services/tenant/organizational_node_levels/create_service.rb

module Tenants
  module OrganizationalNodeLevels
    class CreateService
      include ServiceResultHelper

      attr_reader :params, :tenant, :current_user

      def initialize(params:, tenant:, current_user:)
        @params = params
        @tenant = tenant
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        validation_result = validate_params
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          level = create_level
          return failure(errors: level.errors.full_messages) unless level.persisted?

          set_paper_trail_context

          success(data: level, message: "Organizational level created successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[CreateOrganizationalLevelService] Error: #{e.message}")
        failure(errors: "Failed to create organizational level")
      end

      private

      def validate_params
        required_fields = %i[name level_order]
        missing_fields = required_fields.select { |f| params[f].blank? }

        if missing_fields.any?
          return failure(errors: "Missing required fields: #{missing_fields.join(', ')}")
        end

        # Validar que level_order no esté duplicado
        if OrganizationalNodeLevel.exists?(tenant_id: tenant.id, level_order: params[:level_order])
          return failure(errors: "Level order already exists for this tenant")
        end

        success(data: { valid: true })
      end

      def create_level
        level_params = {
          tenant: tenant,
          name: params[:name],
          slug: params[:slug],
          description: params[:description],
          level_order: params[:level_order],
          allows_vehicles: params[:allows_vehicles].nil? ? true : params[:allows_vehicles],
          allows_users: params[:allows_users].nil? ? true : params[:allows_users],
          is_system: false,
          settings: params[:settings] || {},
          created_by: current_user&.id
        }

        OrganizationalNodeLevel.create!(level_params.compact)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
      end
    end
  end
end
