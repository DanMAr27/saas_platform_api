# app/services/tenant/organizational_nodes/create_service.rb

module Tenants
  module OrganizationalNodes
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
          node = create_node
          return failure(errors: node.errors.full_messages) unless node.persisted?

          set_paper_trail_context

          success(data: node, message: "Organizational node created successfully")
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[CreateOrganizationalNodeService] Error: #{e.message}")
        failure(errors: "Failed to create organizational node")
      end

      private

      def validate_params
        required_fields = %i[name level_id]
        missing_fields = required_fields.select { |f| params[f].blank? }

        if missing_fields.any?
          return failure(errors: "Missing required fields: #{missing_fields.join(', ')}")
        end

        # Validar nivel
        level = OrganizationalNodeLevel.find_by(id: params[:level_id], tenant_id: tenant.id)
        unless level
          return failure(errors: "Level not found or doesn't belong to tenant")
        end

        # Validar padre si se proporciona
        if params[:parent_id]
          parent = OrganizationalNode.find_by(id: params[:parent_id], tenant_id: tenant.id)
          unless parent
            return failure(errors: "Parent node not found or doesn't belong to tenant")
          end

          # Validar que el nivel del padre sea superior
          if parent.level.level_order >= level.level_order
            return failure(errors: "Parent node must be of a higher level")
          end
        end

        success(data: { valid: true })
      end

      def create_node
        node_params = {
          tenant: tenant,
          level_id: params[:level_id],
          parent_id: params[:parent_id],
          name: params[:name],
          code: params[:code],
          description: params[:description],
          address: params[:address],
          city: params[:city],
          state: params[:state],
          postal_code: params[:postal_code],
          country: params[:country],
          phone: params[:phone],
          email: params[:email],
          status: params[:status] || "active",
          metadata: params[:metadata] || {},
          created_by: current_user&.id
        }

        OrganizationalNode.create!(node_params.compact)
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: { performed_action: "create_organizational_node" }
        }
      end
    end
  end
end
