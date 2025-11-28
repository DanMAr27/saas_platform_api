# app/api/v1/entities/user_with_membership_entity.rb

module V1
  module Entities
    # Entity compuesta para usuario con su membresía en un tenant
    # Incluye datos del usuario, rol y scopes

    class UserWithMembershipEntity < Grape::Entity
      # Datos del usuario
      expose :id, documentation: { type: "Integer" }
      expose :email, documentation: { type: "String" }
      expose :first_name, documentation: { type: "String" }
      expose :last_name, documentation: { type: "String" }
      expose :full_name, documentation: { type: "String" }
      expose :phone, documentation: { type: "String" }
      expose :avatar_url, documentation: { type: "String" }

      # Estado del usuario
      expose :email_verified do |user|
        user.email_verified?
      end

      expose :active do |user|
        user.active?
      end

      # Información de la membresía
      expose :membership, using: TenantMembershipEntity,
             if: ->(user, opts) { opts[:membership].present? } do |user, opts|
        opts[:membership]
      end

      # Scopes (si se solicitan)
      expose :scopes, if: ->(user, opts) { opts[:include_scopes] } do |user, opts|
        tenant_id = opts[:tenant_id] || opts[:membership]&.tenant_id

        {
          nodes: user.user_node_scopes
                    .where(tenant_id: tenant_id)
                    .kept
                    .includes(:organizational_node)
                    .map { |scope|
                      UserNodeScopeEntity.represent(
                        scope,
                        include_node: true,
                        show_timestamps: false
                      )
                    },

          vehicles: user.user_vehicle_scopes
                       .where(tenant_id: tenant_id)
                       .kept
                       .includes(:vehicle)
                       .map { |scope|
                         UserVehicleScopeEntity.represent(
                           scope,
                           include_vehicle: true,
                           show_timestamps: false
                         )
                       }
        }
      end

      # Timestamps (si se solicitan)
      with_options(if: ->(user, opts) { opts[:show_timestamps] }) do
        expose :created_at, format_with: :iso_timestamp
        expose :last_login_at, format_with: :iso_timestamp
      end

      # Estadísticas (si se solicitan)
      expose :stats, if: ->(user, opts) { opts[:show_stats] } do |user, opts|
        tenant_id = opts[:tenant_id] || opts[:membership]&.tenant_id

        {
          node_scopes_count: user.user_node_scopes
                                .where(tenant_id: tenant_id)
                                .kept
                                .count,
          vehicle_scopes_count: user.user_vehicle_scopes
                                   .where(tenant_id: tenant_id)
                                   .kept
                                   .count,
          sign_in_count: user.sign_in_count
        }
      end
    end
  end
end
