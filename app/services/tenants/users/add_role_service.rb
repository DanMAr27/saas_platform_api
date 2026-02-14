# app/services/tenants/users/add_role_service.rb

module Tenants
  module Users
    class AddRoleService
      include ServiceResultHelper

      attr_reader :user, :tenant, :role_slug, :node_scopes, :vehicle_scopes, :current_user

      def initialize(user:, tenant:, role_slug:, node_scopes: nil, vehicle_scopes: nil, current_user:)
        @user = user
        @tenant = tenant
        @role_slug = role_slug
        @node_scopes = node_scopes
        @vehicle_scopes = vehicle_scopes
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar que el usuario ya tenga acceso al tenant
        unless user.has_tenant_access?(tenant.id)
          return failure(errors: "User must have existing access to tenant before adding additional roles")
        end

        # Buscar rol
        role = Role.tenant_roles.find_by(slug: role_slug)
        unless role
          return failure(errors: "Invalid role")
        end

        # Verificar que no tenga ya este rol
        existing_membership = user.tenant_memberships
                                  .where(tenant_id: tenant.id, role_id: role.id)
                                  .first

        if existing_membership
          if existing_membership.deleted?
            return failure(errors: "Cannot add role that was previously removed")
          else
            return failure(errors: "User already has this role in this tenant")
          end
        end

        ActiveRecord::Base.transaction do
          # Asignar scopes si se proporcionaron (PRIMERO, para pasar validaciones de membresía)
          if role.requires_scope? || node_scopes.present? || vehicle_scopes.present?
            scopes_result = assign_scopes(role)
            return scopes_result if scopes_result.failure?
          end

          # Crear nueva membresía con el rol adicional
          membership = TenantMembership.create!(
            user: user,
            tenant: tenant,
            role_id: role.id,
            status: "active",
            is_primary_admin: false,
            is_default: false, # Los roles adicionales nunca son default
            created_by: current_user.id
          )

          # Configurar PaperTrail
          set_paper_trail_context(role)

          success(
            data: { membership: membership.reload },
            message: "Role '#{role.name}' added successfully"
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[AddRoleService] Error: #{e.message}")
        failure(errors: "Failed to add role")
      end

      private

      def assign_scopes(role)
        # Asignar node scopes
        if node_scopes.present?
          node_scopes.each do |node_scope_params|
            node = OrganizationalNode.find(node_scope_params[:organizational_node_id])

            unless node.tenant_id == tenant.id
              return failure(errors: "Node does not belong to this tenant")
            end

            UserNodeScope.create!(
              user: user,
              organizational_node: node,
              tenant: tenant,
              role: role,
              access_type: node_scope_params[:access_type] || "read",
              include_children: node_scope_params.fetch(:include_children, true),
              created_by: current_user.id
            )
          end
        end

        # Asignar vehicle scopes
        if vehicle_scopes.present?
          vehicle_scopes.each do |vehicle_scope_params|
            vehicle = Vehicle.find(vehicle_scope_params[:vehicle_id])

            unless vehicle.tenant_id == tenant.id
              return failure(errors: "Vehicle does not belong to this tenant")
            end

            UserVehicleScope.create!(
              user: user,
              vehicle: vehicle,
              tenant: tenant,
              role: role,
              access_type: vehicle_scope_params[:access_type] || "read",
              valid_from: vehicle_scope_params[:valid_from],
              valid_until: vehicle_scope_params[:valid_until],
              created_by: current_user.id
            )
          end
        end

        success(data: { assigned: true })
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotFound => e
        failure(errors: "Resource not found: #{e.message}")
      end

      def set_paper_trail_context(role)
        PaperTrail.request.whodunnit = current_user.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "add_user_role",
            role_added: role.name
          }
        }
      end
    end
  end
end
