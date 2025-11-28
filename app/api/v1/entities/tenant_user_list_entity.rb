# app/api/entities/v1/tenant/tenant_user_list_entity.rb
# Entity para LISTADO de usuarios (más simple, sin scopes)

module V1
  module Entities
    class TenantUserListEntity < Grape::Entity
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
      # MEMBERSHIP SIMPLIFICADA
      # ============================================
      expose :membership_id, documentation: { type: "Integer" } do |membership|
        membership.id
      end

      expose :status, documentation: { type: "String" } do |membership|
        membership.status
      end

      expose :is_primary_admin, documentation: { type: "Boolean" } do |membership|
        membership.is_primary_admin?
      end

      expose :is_default, documentation: { type: "Boolean" } do |membership|
        membership.is_default?
      end

      # ============================================
      # ROL SIMPLIFICADO
      # ============================================
      expose :role, documentation: { type: "Object" } do |membership|
        role = membership.role

        {
          id: role.id,
          slug: role.slug,
          name: role.name
        }
      end

      # ============================================
      # TIMESTAMPS
      # ============================================
      expose :joined_at, documentation: { type: "DateTime" } do |membership|
        membership.created_at&.iso8601
      end

      expose :last_sign_in_at, documentation: { type: "DateTime" } do |membership|
        membership.user.last_sign_in_at&.iso8601
      end
    end
  end
end
