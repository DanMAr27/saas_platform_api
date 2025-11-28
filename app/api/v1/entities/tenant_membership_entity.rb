# app/api/v1/entities/tenant_membership_entity.rb

module V1
  module Entities
    # Entity para serializar membresías de tenant

    class TenantMembershipEntity < Grape::Entity
      # Campos básicos
      expose :id, documentation: { type: "Integer", desc: "Membership ID" }
      expose :role_id, documentation: { type: "Integer" }
      expose :role_slug, documentation: { type: "String" } do |membership|
        membership.role&.slug || membership.role
      end
      expose :role_name, documentation: { type: "String" } do |membership|
        membership.role&.name || membership.role&.titleize
      end
      expose :status, documentation: { type: "String", desc: "Membership status" }
      expose :is_primary_admin, documentation: { type: "Boolean" }
      expose :is_default, documentation: { type: "Boolean" }

      # Usuario asociado (opcional)
      expose :user, using: UserEntity,
             if: ->(membership, opts) { opts[:include_user] }

      # Tenant asociado (opcional)
      expose :tenant, using: TenantEntity,
             if: ->(membership, opts) { opts[:include_tenant] }

      # Solo IDs si no se incluyen entidades completas
      expose :user_id, unless: ->(membership, opts) { opts[:include_user] }
      expose :tenant_id, unless: ->(membership, opts) { opts[:include_tenant] }

      # Información de invitación
      expose :invitation_pending,
             if: ->(membership, opts) { membership.invited? } do |membership|
        membership.invitation_pending?
      end

      expose :invitation_sent_at,
             format_with: :iso_timestamp,
             if: ->(membership, opts) { membership.invited? }

      expose :invitation_accepted_at,
             format_with: :iso_timestamp,
             if: ->(membership, opts) { membership.invitation_accepted_at.present? }

      # Timestamps
      expose :created_at,
             format_with: :iso_timestamp,
             if: ->(membership, opts) { opts[:show_timestamps] }

      expose :updated_at,
             format_with: :iso_timestamp,
             if: ->(membership, opts) { opts[:show_timestamps] }
    end
  end
end
