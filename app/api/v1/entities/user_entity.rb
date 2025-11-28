# app/api/v1/entities/user_entity.rb

module V1
  module Entities
    # Entity para serializar usuarios
    # Controla qué campos se exponen en la API según el contexto

    class UserEntity < Grape::Entity
      # Campos básicos (siempre expuestos)
      expose :id, documentation: { type: "Integer", desc: "User ID" }
      expose :email, documentation: { type: "String", desc: "User email" }
      expose :first_name, documentation: { type: "String", desc: "First name" }
      expose :last_name, documentation: { type: "String", desc: "Last name" }
      expose :full_name, documentation: { type: "String", desc: "Full name" }

      # Campos opcionales (según contexto)
      expose :phone, if: ->(user, opts) { opts[:show_details] }
      expose :avatar_url, if: ->(user, opts) { opts[:show_details] }

      # Estado
      expose :email_verified, as: :email_verified do |user|
        user.email_verified?
      end

      expose :active, as: :active do |user|
        user.active?
      end

      # Timestamps
      expose :created_at, format_with: :iso_timestamp,
             if: ->(user, opts) { opts[:show_details] }
      expose :last_login_at, format_with: :iso_timestamp,
             if: ->(user, opts) { opts[:show_details] }

      # Contexto y memberships (solo si está disponible)
      expose :context, if: ->(user, opts) { opts[:context].present? } do |user, opts|
        opts[:context]
      end

      expose :tenant_id, if: ->(user, opts) { opts[:tenant_id].present? } do |user, opts|
        opts[:tenant_id]
      end

      # Resumen (para listas)
      with_options(if: ->(user, opts) { opts[:type] == :summary }) do
        expose :id
        expose :email
        expose :full_name
        expose :avatar_url
      end

      # Detalles completos
      with_options(if: ->(user, opts) { opts[:type] == :detailed }) do
        expose :phone
        expose :avatar_url
        expose :email_verified_at, format_with: :iso_timestamp
        expose :invitation_accepted_at, format_with: :iso_timestamp
        expose :created_at, format_with: :iso_timestamp
        expose :updated_at, format_with: :iso_timestamp
        expose :last_login_at, format_with: :iso_timestamp
        expose :sign_in_count
      end
    end
  end
end
