# app/api/entities/v1/tenant/tenant_user_list_entity.rb
# Entity para LISTADO de usuarios con TODAS sus membresías en el tenant

module V1
  module Entities
    class TenantUserListEntity < Grape::Entity
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
      # MEMBRESÍAS EN EL TENANT (ARRAY)
      # ============================================
      expose :memberships, documentation: {
        type: "Array",
        desc: "All roles/memberships for this user in the tenant"
      } do |user, options|
        tenant_id = options[:tenant_id]

        # Obtener TODAS las membresías activas del usuario en este tenant
        memberships = user.tenant_memberships
                          .kept
                          .where(tenant_id: tenant_id)
                          .includes(:role)
                          .order("roles.priority ASC")

        memberships.map do |membership|
          {
            id: membership.id,
            role: {
              id: membership.role.id,
              slug: membership.role.slug,
              name: membership.role.name,
              priority: membership.role.priority
            },
            status: membership.status,
            is_primary_admin: membership.is_primary_admin?,
            is_default: membership.is_default?,
            joined_at: membership.created_at&.iso8601,
            invitation_pending: membership.invitation_pending?,
            invitation_expired: membership.invitation_expired?
          }
        end
      end

      # ============================================
      # ROL PRINCIPAL (El de mayor prioridad)
      # ============================================
      expose :primary_role, documentation: {
        type: "Object",
        desc: "Primary role (highest priority) for display purposes"
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
            slug: primary_membership.role.slug,
            name: primary_membership.role.name
          }
        else
          nil
        end
      end

      # ============================================
      # SCOPE SUMMARY (Para la columna "Scope")
      # ============================================
      expose :scope_summary, documentation: {
        type: "String",
        desc: "Human-readable scope description"
      } do |user, options|
        tenant_id = options[:tenant_id]

        # Verificar si tiene acceso total (es admin del tenant)
        is_admin = user.tenant_memberships
                       .kept
                       .active
                       .where(tenant_id: tenant_id)
                       .joins(:role)
                       .exists?(roles: { slug: "tenant_admin" })

        if is_admin
          "Acceso total"
        else
          # Contar nodos y vehículos (si tienes estas asociaciones)
          # Si no las tienes aún, puedes dejarlo en "Acceso limitado"
          "Acceso limitado"
        end
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
