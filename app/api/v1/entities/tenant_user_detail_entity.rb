# app/api/entities/v1/tenant/tenant_user_detail_entity.rb
# Entity para DETALLE de usuario (completa, con scopes opcionales)

module V1
  module Entities
    class TenantUserDetailEntity < Grape::Entity
      # ============================================
      # DATOS DEL USUARIO
      # ============================================
      expose :id, documentation: { type: "Integer", desc: "User ID" } do |membership|
        membership.user.id
      end

      expose :email, documentation: { type: "String" } do |membership|
        membership.user.email
      end

      expose :first_name, documentation: { type: "String" } do |membership|
        membership.user.first_name
      end

      expose :last_name, documentation: { type: "String" } do |membership|
        membership.user.last_name
      end

      expose :full_name, documentation: { type: "String" } do |membership|
        membership.user.full_name
      end

      expose :phone, documentation: { type: "String" } do |membership|
        membership.user.phone
      end

      # ============================================
      # ESTADO DEL USUARIO
      # ============================================
      expose :active, documentation: { type: "Boolean" } do |membership|
        membership.user.active?
      end

      expose :locked, documentation: { type: "Boolean" } do |membership|
        membership.user.locked?
      end

      expose :email_verified, documentation: { type: "Boolean" } do |membership|
        membership.user.email_verified?
      end

      # ============================================
      # MEMBERSHIP COMPLETA
      # ============================================
      expose :membership, documentation: { type: "Object" } do |membership|
        {
          id: membership.id,
          tenant_id: membership.tenant_id,
          status: membership.status,
          is_primary_admin: membership.is_primary_admin?,
          is_default: membership.is_default?,
          joined_at: membership.created_at&.iso8601,
          updated_at: membership.updated_at&.iso8601
        }
      end

      # ============================================
      # ROL COMPLETO
      # ============================================
      expose :role, documentation: { type: "Object" } do |membership|
        role = membership.role

        {
          id: role.id,
          slug: role.slug,
          name: role.name,
          priority: role.priority
        }
      end

      # ============================================
      # SCOPES (NODOS Y VEHÍCULOS)
      # ============================================
      expose :scopes,
             if: ->(membership, options) { options[:include_scopes] },
             documentation: { type: "Object" } do |membership, options|
        tenant_id = options[:tenant_id] || membership.tenant_id
        user_id = membership.user_id

        node_scopes = UserNodeScope
                        .where(user_id: user_id, tenant_id: tenant_id)
                        .kept
                        .includes(:organizational_node)

        vehicle_scopes = UserVehicleScope
                          .where(user_id: user_id, tenant_id: tenant_id)
                          .kept
                          .includes(:vehicle)

        {
          nodes: node_scopes.map do |scope|
            {
              id: scope.id,
              node_id: scope.organizational_node_id,
              node_name: scope.organizational_node.name,
              node_code: scope.organizational_node.code,
              node_path: scope.organizational_node.full_path,
              access_type: scope.access_type,
              include_children: scope.include_children,
              created_at: scope.created_at&.iso8601
            }
          end,

          vehicles: vehicle_scopes.map do |scope|
            {
              id: scope.id,
              vehicle_id: scope.vehicle_id,
              vehicle_name: scope.vehicle.name,
              license_plate: scope.vehicle.license_plate,
              vehicle_code: scope.vehicle.code,
              access_type: scope.access_type,
              valid_from: scope.valid_from&.iso8601,
              valid_until: scope.valid_until&.iso8601,
              is_active: scope.active?,
              created_at: scope.created_at&.iso8601
            }
          end,

          summary: {
            total_nodes: node_scopes.count,
            total_vehicles: vehicle_scopes.count,
            active_vehicles: vehicle_scopes.select(&:active?).count,
            expired_vehicles: vehicle_scopes.reject(&:active?).count
          }
        }
      end

      # ============================================
      # INFORMACIÓN ADICIONAL
      # ============================================
      expose :last_sign_in_at, documentation: { type: "DateTime" } do |membership|
        membership.user.last_sign_in_at&.iso8601
      end

      expose :invitation_status, documentation: { type: "Object" } do |membership|
        user = membership.user

        {
          pending: user.invitation_pending?,
          expired: user.invitation_expired?,
          accepted_at: user.invitation_accepted_at&.iso8601,
          invited_by: user.invited_by&.full_name
        }
      end

      # ============================================
      # TIMESTAMPS
      # ============================================
      expose :created_at, documentation: { type: "DateTime" } do |membership|
        membership.created_at&.iso8601
      end

      expose :updated_at, documentation: { type: "DateTime" } do |membership|
        membership.updated_at&.iso8601
      end
    end
  end
end
