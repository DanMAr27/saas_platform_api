# app/api/v1/entities/role_entity.rb

module V1
  module Entities
    # Entity para roles con soporte para scope flags

    class RoleEntity < Grape::Entity
      expose :id, documentation: { type: "Integer" }
      expose :name, documentation: { type: "String" }
      expose :slug, documentation: { type: "String" }
      expose :description, documentation: { type: "String" }
      expose :context, documentation: { type: "String", values: %w[platform tenant] }
      expose :is_system, documentation: { type: "Boolean" }
      expose :priority, documentation: { type: "Integer" }

      # 🆕 NUEVO: Información de scopes
      expose :scope_config, documentation: { type: "Object" } do
        expose :requires_any_scope, documentation: { type: "Boolean" }
        expose :allows_node_scope, documentation: { type: "Boolean" }
        expose :allows_vehicle_scope, documentation: { type: "Boolean" }
        expose :scope_type, documentation: {
          type: "String",
          desc: "Type of scope: 'node', 'vehicle', or null"
        }
        expose :description, as: :scope_description, documentation: {
          type: "String",
          desc: "Human-readable description of scope requirements"
        } do |role|
          role.scope_requirements_description
        end
      end

      # 🔄 DEPRECATED pero mantenido por compatibilidad
      expose :requires_scope, documentation: {
        type: "Boolean",
        desc: "DEPRECATED: Use scope_config.requires_any_scope instead"
      } do |role|
        role.requires_any_scope?
      end

      # Settings (si se solicitan)
      expose :settings, if: ->(role, opts) { opts[:show_settings] }, documentation: {
        type: "Object"
      }

      # Estadísticas de uso (si se solicitan)
      expose :usage_count, if: ->(role, opts) { opts[:show_usage] }, documentation: {
        type: "Integer",
        desc: "Number of users with this role"
      } do |role|
        role.usage_count
      end

      # 🆕 NUEVO: Uso en tenant específico
      expose :usage_in_tenant, if: ->(role, opts) { opts[:tenant_id].present? }, documentation: {
        type: "Object"
      } do |role, opts|
        tenant_id = opts[:tenant_id]
        {
          total_users: TenantMembership.where(role_id: role.id, tenant_id: tenant_id).kept.count,
          active_users: TenantMembership.where(role_id: role.id, tenant_id: tenant_id, status: "active").kept.count,
          invited_users: TenantMembership.where(role_id: role.id, tenant_id: tenant_id, status: "invited").kept.count
        }
      end

      # Timestamps
      with_options(if: ->(role, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end

      # 🆕 NUEVO: Formato detallado con toda la información
      class Detailed < RoleEntity
        expose :settings
        expose :usage_count
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
      end
    end
  end
end
