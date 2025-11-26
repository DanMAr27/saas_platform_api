# app/api/v1/entities/tenant_entity.rb

module V1
module Entities
  # Entity para serializar tenants
  # Controla qué información del tenant se expone en la API

  class TenantEntity < Grape::Entity
    # Campos básicos (siempre expuestos)
    expose :id, documentation: { type: "Integer", desc: "Tenant ID" }
    expose :name, documentation: { type: "String", desc: "Tenant name" }
    expose :slug, documentation: { type: "String", desc: "URL-friendly identifier" }
    expose :status, documentation: { type: "String", desc: "Tenant status" }
    expose :plan, documentation: { type: "String", desc: "Subscription plan" }

    # Información adicional (según contexto)
    expose :domain, if: ->(tenant, opts) { opts[:show_details] }
    expose :legal_name, if: ->(tenant, opts) { opts[:show_details] }
    expose :country, if: ->(tenant, opts) { opts[:show_details] }
    expose :timezone, if: ->(tenant, opts) { opts[:show_details] }
    expose :locale, if: ->(tenant, opts) { opts[:show_details] }
    expose :currency, if: ->(tenant, opts) { opts[:show_details] }

    # Límites del plan
    expose :max_users, if: ->(tenant, opts) { opts[:show_limits] }
    expose :max_storage_gb, if: ->(tenant, opts) { opts[:show_limits] }

    # Información de trial
    expose :trial_ends_at,
            format_with: :iso_timestamp,
            if: ->(tenant, opts) { tenant.trial? }

    expose :trial_days_remaining, if: ->(tenant, opts) { tenant.trial? } do |tenant|
      tenant.trial_days_remaining
    end

    # Información de suscripción
    expose :subscription_starts_at,
            format_with: :iso_timestamp,
            if: ->(tenant, opts) { opts[:show_subscription] && tenant.active? }

    # Timestamps
    expose :created_at,
            format_with: :iso_timestamp,
            if: ->(tenant, opts) { opts[:show_timestamps] }

    expose :updated_at,
            format_with: :iso_timestamp,
            if: ->(tenant, opts) { opts[:show_timestamps] }

    # Resumen (para listas)
    with_options(if: ->(tenant, opts) { opts[:type] == :summary }) do
      expose :id
      expose :name
      expose :slug
      expose :status
      expose :plan
    end

    # Detalles completos
    with_options(if: ->(tenant, opts) { opts[:type] == :detailed }) do
      expose :domain
      expose :legal_name
      expose :tax_id
      expose :address
      expose :city
      expose :country
      expose :timezone
      expose :locale
      expose :currency
      expose :max_users
      expose :max_storage_gb
      expose :trial_ends_at, format_with: :iso_timestamp
      expose :subscription_starts_at, format_with: :iso_timestamp
      expose :created_at, format_with: :iso_timestamp
      expose :updated_at, format_with: :iso_timestamp

      # Estadísticas
      expose :users_count do |tenant|
        tenant.active_users.count
      end

      expose :remaining_user_slots do |tenant|
        tenant.remaining_user_slots
      end
    end
  end
end
end
