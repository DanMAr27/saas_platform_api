# app/services/tenants/organizational_nodes/create_service.rb
# Servicio para crear nodos organizacionales con validaciones completas

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
        # Validaciones previas
        validation_result = validate_params
        return validation_result if validation_result.failure?

        # Crear el nodo
        ActiveRecord::Base.transaction do
          node = create_node
          invalidate_cache
          set_paper_trail_context

          success(
            data: node,
            message: "Organizational node created successfully",
            meta: { node_id: node.id, full_path: node.full_path }
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[CreateOrganizationalNodeService] Error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        failure(errors: "Failed to create organizational node: #{e.message}")
      end

      private

      def validate_params
        # Validar campos requeridos
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
          parent_validation = validate_parent(level)
          return parent_validation if parent_validation.failure?
        else
          # Si no hay padre, debe ser un nodo raíz (nivel 1)
          unless level.level_order == 1
            return failure(errors: "Only level 1 nodes can be root nodes")
          end
        end

        # Validar código único si se proporciona
        if params[:code].present?
          existing = OrganizationalNode.where(
            tenant_id: tenant.id,
            code: params[:code]
          ).where.not(deleted_at: nil).exists?

          if existing
            return failure(errors: "Code already exists in this tenant")
          end
        end

        success(data: { valid: true })
      end

      def validate_parent(level)
        parent = OrganizationalNode.find_by(
          id: params[:parent_id],
          tenant_id: tenant.id
        )

        unless parent
          return failure(errors: "Parent node not found or doesn't belong to tenant")
        end

        # Validar que el padre esté activo
        unless parent.status == "active"
          return failure(errors: "Parent node must be active")
        end

        # Validar que el nivel del padre sea inmediatamente superior
        expected_parent_level = level.level_order - 1
        unless parent.level.level_order == expected_parent_level
          return failure(
            errors: "Parent node must be of level #{expected_parent_level}, got level #{parent.level.level_order}"
          )
        end

        # Validar que el padre pueda tener hijos
        unless parent.level.next_level.present?
          return failure(errors: "Parent node's level doesn't allow children")
        end

        success(data: { parent: parent })
      end

      def create_node
        node_params = build_node_params

        node = OrganizationalNode.new(node_params)
        node.save!

        # Recargar para obtener closure table actualizada
        node.reload
        node
      end

      def build_node_params
        {
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
        }.compact
      end

      def invalidate_cache
        Rails.cache.delete("tenant:#{tenant.id}:org_tree")
      end

      def set_paper_trail_context
        PaperTrail.request.whodunnit = current_user&.id
        PaperTrail.request.controller_info = {
          metadata: {
            action: "create_organizational_node",
            tenant_id: tenant.id
          }
        }
      end
    end
  end
end
