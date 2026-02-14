# app/api/entities/v1/tenant/tenant_user_detail_entity.rb
# Entity para DETALLE de usuario (completa, con todas sus membresías y scopes)

module V1
  module Entities
    class TenantUserDetailEntity < Grape::Entity
      # ============================================
      # DATOS DEL USUARIO
      # ============================================
      expose :id, documentation: {
        type: "Integer",
        desc: "User ID"
      }

      expose :email, documentation: {
        type: "String"
      }

      expose :first_name, documentation: {
        type: "String"
      }

      expose :last_name, documentation: {
        type: "String"
      }

      expose :full_name, documentation: {
        type: "String"
      }

      expose :phone, documentation: {
        type: "String"
      }

      expose :avatar_url, documentation: {
        type: "String"
      }

      # ============================================
      # ESTADO DEL USUARIO
      # ============================================
      expose :active, documentation: {
        type: "Boolean",
        desc: "User account is active (not deleted or locked)"
      } do |user|
        user.active?
      end

      expose :locked, documentation: {
        type: "Boolean"
      } do |user|
        user.locked?
      end

      expose :email_verified, documentation: {
        type: "Boolean"
      } do |user|
        user.email_verified?
      end

      # ============================================
      # TODAS LAS MEMBRESÍAS EN EL TENANT
      # ============================================
      expose :memberships, documentation: {
        type: "Array",
        desc: "All roles/memberships for this user in the tenant"
      } do |user, options|
        tenant_id = options[:tenant_id]

        memberships = user.tenant_memberships
                          .kept
                          .where(tenant_id: tenant_id)
                          .includes(:role)
                          .order("roles.priority ASC")

        memberships.map do |membership|
          # Obtener scopes específicos para este rol
          node_scopes = user.user_node_scopes
                            .kept
                            .where(tenant_id: tenant_id, role_id: membership.role_id)

          vehicle_scopes = user.user_vehicle_scopes
                               .kept
                               .where(tenant_id: tenant_id, role_id: membership.role_id)
                               .includes(:vehicle)

          {
            id: membership.id,
            role: {
              id: membership.role.id,
              slug: membership.role.slug,
              name: membership.role.name,
              priority: membership.role.priority,
              # 🆕 Información de scopes permitidos
              allows_node_scope: membership.role.allows_node_scope?,
              allows_vehicle_scope: membership.role.allows_vehicle_scope?,
              requires_any_scope: membership.role.requires_any_scope?
            },
            status: membership.status,
            is_primary_admin: membership.is_primary_admin?,
            is_default: membership.is_default?,
            joined_at: membership.created_at&.iso8601,
            updated_at: membership.updated_at&.iso8601,
            invitation_pending: membership.invitation_pending?,
            invitation_expired: membership.invitation_expired?,
            # Scopes específicos del rol
            node_scopes: node_scopes.map do |ns|
              {
                id: ns.id,
                organizational_node_id: ns.organizational_node_id,
                node_name: ns.organizational_node&.name,
                access_type: ns.access_type,
                include_children: ns.include_children?
              }
            end,
            vehicle_scopes: vehicle_scopes.map do |vs|
              {
                id: vs.id,
                vehicle_id: vs.vehicle_id,
                vehicle_name: vs.vehicle&.name,
                license_plate: vs.vehicle&.license_plate,
                access_type: vs.access_type,
                valid_from: vs.valid_from,
                valid_until: vs.valid_until
              }
            end
          }
        end
      end

      # ============================================
      # ROL PRINCIPAL (para compatibilidad)
      # ============================================
      expose :primary_role, documentation: {
        type: "Object",
        desc: "Primary role (highest priority)"
      } do |user, options|
        tenant_id = options[:tenant_id]

        primary_membership = user.tenant_memberships
                                 .kept
                                 .where(tenant_id: tenant_id)
                                 .includes(:role)
                                 .order("roles.priority ASC")
                                 .first

        if primary_membership
          {
            id: primary_membership.role.id,
            slug: primary_membership.role.slug,
            name: primary_membership.role.name,
            priority: primary_membership.role.priority
          }
        else
          nil
        end
      end

      # ============================================
      # SCOPES (NODOS Y VEHÍCULOS) - CONDICIONAL SEGÚN ROLES
      # ============================================
      expose :scopes,
             documentation: {
               type: "Object",
               desc: "Access scopes based on role capabilities"
             } do |user, options|
        tenant_id = options[:tenant_id]

        # Determinar qué tipos de scopes necesita el usuario según sus roles
        user_roles = user.tenant_memberships
                        .kept
                        .where(tenant_id: tenant_id)
                        .includes(:role)
                        .map(&:role)

        has_node_scope_roles = user_roles.any?(&:allows_node_scope?)
        has_vehicle_scope_roles = user_roles.any?(&:allows_vehicle_scope?)

        result = {}

        # ============================================
        # NODES - Solo si tiene roles que permiten node scopes
        # ============================================
        if has_node_scope_roles
          # Obtener todos los nodos activos del tenant
          all_nodes = OrganizationalNode
                        .where(tenant_id: tenant_id)
                        .active
                        .includes(:level, :children, :ancestors)

          # Construir el árbol con información de selección del usuario
          query = OrganizationalNodesScopeQuery.new(all_nodes, user: user)
          tree_result = query.selection_tree

          # Manejar el resultado del query
          if tree_result.is_a?(Hash)
            tree_data = tree_result[:tree] || tree_result["tree"] || []
            metadata = tree_result[:metadata] || tree_result["metadata"] || {}
          else
            tree_data = tree_result
            metadata = {}
          end

          # Metadata de scopes
          stored_scopes = UserNodeScope
                            .where(user_id: user.id, tenant_id: tenant_id)
                            .kept

          stored_count = stored_scopes.count

          # Extraer metadata de forma segura
          total_coverage = metadata[:total_coverage] || metadata["total_coverage"] || 0
          optimization_ratio = metadata[:optimization_ratio] || metadata["optimization_ratio"] || {}
          saved_records = if optimization_ratio.is_a?(Hash)
                            optimization_ratio[:saved_records] || optimization_ratio["saved_records"] || 0
          else
                            0
          end

          result[:nodes_tree] = V1::Entities::OrganizationalNodeSelectionEntity.represent(tree_data)
          result[:nodes_metadata] = V1::Entities::OrganizationalNodeSelectionEntity::SelectionTreeMetadataEntity.represent(metadata)
          result[:nodes_summary] = {
            total_stored_nodes: stored_count,
            total_effective_nodes: total_coverage,
            optimization_saved: saved_records
          }
        end

        # ============================================
        # VEHÍCULOS - Solo si tiene roles que permiten vehicle scopes
        # ============================================
        if has_vehicle_scope_roles
          vehicle_scopes = UserVehicleScope
                            .where(user_id: user.id, tenant_id: tenant_id)
                            .kept
                            .includes(:vehicle)

          active_vehicles_count = vehicle_scopes.select(&:active?).count
          total_vehicles_count = vehicle_scopes.count

          vehicles = vehicle_scopes.map do |scope|
            {
              id: scope.id,
              vehicle_id: scope.vehicle_id,
              vehicle_name: scope.vehicle.name,
              license_plate: scope.vehicle.license_plate,
              vehicle_code: scope.vehicle.fleet_number,
              access_type: scope.access_type,
              valid_from: scope.valid_from&.iso8601,
              valid_until: scope.valid_until&.iso8601,
              is_active: scope.active?,
              created_at: scope.created_at&.iso8601
            }
          end

          result[:vehicles] = vehicles
          result[:vehicles_summary] = {
            total_vehicles: total_vehicles_count,
            active_vehicles: active_vehicles_count,
            expired_vehicles: total_vehicles_count - active_vehicles_count
          }
        end

        # ============================================
        # METADATA GENERAL
        # ============================================
        result[:scope_capabilities] = {
          has_node_scopes: has_node_scope_roles,
          has_vehicle_scopes: has_vehicle_scope_roles,
          has_full_access: user_roles.any? { |r| !r.requires_any_scope? }
        }

        result
      end

      # ============================================
      # INFORMACIÓN DE INVITACIÓN
      # ============================================
      expose :invitation_status, documentation: {
        type: "Object"
      } do |user|
        {
          pending: user.invitation_pending?,
          expired: user.invitation_expired?,
          accepted_at: user.invitation_accepted_at&.iso8601,
          invited_by: user.invited_by&.full_name
        }
      end

      # ============================================
      # ÚLTIMO ACCESO
      # ============================================
      expose :last_sign_in_at, documentation: {
        type: "DateTime"
      } do |user|
        user.last_sign_in_at&.iso8601
      end

      expose :last_sign_in_ip, documentation: {
        type: "String"
      }

      expose :current_sign_in_at, documentation: {
        type: "DateTime"
      } do |user|
        user.current_sign_in_at&.iso8601
      end

      expose :sign_in_count, documentation: {
        type: "Integer"
      }

      # ============================================
      # TIMESTAMPS
      # ============================================
      expose :created_at, documentation: {
        type: "DateTime"
      } do |user|
        user.created_at&.iso8601
      end

      expose :updated_at, documentation: {
        type: "DateTime"
      } do |user|
        user.updated_at&.iso8601
      end
    end
  end
end
