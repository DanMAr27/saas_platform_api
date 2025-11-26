# frozen_string_literal: true

module Platform
  module Tenants
    # Servicio para invitar un usuario a un tenant
    # Crea el usuario si no existe y crea la membresía con estado 'invited'
    #
    # Uso:
    #   result = InviteService.call(
    #     tenant: tenant,
    #     email: 'newuser@example.com',
    #     first_name: 'Jane',
    #     last_name: 'Doe',
    #     role: 'manager',
    #     invited_by: current_user
    #   )

    class InviteService
      include ServiceResultHelper

      attr_reader :tenant, :params, :invited_by

      def initialize(tenant:, params:, invited_by:)
        @tenant = tenant
        @params = params
        @invited_by = invited_by
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar parámetros
        validation_result = validate_params
        return validation_result if validation_result.failure?

        # Validar límite de usuarios del tenant
        return failure(errors: "User limit reached for this tenant") if tenant.user_limit_reached?

        # Validar que invited_by tenga permisos
        return failure(errors: "Not authorized") unless can_invite?

        ActiveRecord::Base.transaction do
          # Encontrar o crear usuario
          user_result = find_or_create_user
          return user_result if user_result.failure?

          user = user_result.data

          # Verificar que no tenga membresía activa
          if user.has_tenant_access?(tenant.id)
            return failure(errors: "User already has access to this tenant")
          end

          # Crear membresía de invitación
          membership = create_invitation_membership(user)
          return membership if membership.failure?

          # Configurar PaperTrail
          set_paper_trail_context

          # TODO: Enviar email de invitación (Fase futura)
          # InvitationMailer.invite(membership.data).deliver_later

          success(
            data: {
              user: user,
              membership: membership.data,
              invitation_token: membership.data.invitation_token
            },
            message: "User invited successfully"
          )
        end
      rescue StandardError => e
        Rails.logger.error("[InviteUserService] Error: #{e.message}")
        failure(errors: "Failed to invite user")
      end

      private

      # Validar parámetros
      def validate_params
        required_fields = %i[email first_name last_name role]
        missing_fields = required_fields.select { |field| params[field].blank? }

        if missing_fields.any?
          return failure(
            errors: "Missing required fields: #{missing_fields.join(', ')}"
          )
        end

        # Validar email
        unless params[:email] =~ URI::MailTo::EMAIL_REGEXP
          return failure(errors: "Invalid email format")
        end

        # Validar rol
        unless TenantMembership.ROLES.include?(params[:role])
          return failure(
            errors: "Invalid role. Must be one of: #{TenantMembership.ROLES.join(', ')}"
          )
        end

        success(data: { valid: true })
      end

      # Verificar permisos del invitador
      def can_invite?
        # El invitador debe ser admin o manager del tenant
        role = invited_by.tenant_role(tenant.id)
        role.in?(%w[admin manager])
      end

      # Encontrar o crear usuario
      def find_or_create_user
        email = params[:email].downcase.strip
        existing_user = User.find_by_email(email)

        if existing_user
          # Usuario existe
          if existing_user.deleted?
            return failure(errors: "User account is deactivated")
          end

          return success(data: existing_user)
        end

        # Crear nuevo usuario sin password (lo establecerá al aceptar invitación)
        user_params = {
          email: email,
          first_name: params[:first_name],
          last_name: params[:last_name],
          phone: params[:phone],
          password: generate_temporary_password,
          password_confirmation: generate_temporary_password,
          invited_by: invited_by
        }

        user = User.create!(user_params)
        success(data: user)
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      # Crear membresía de invitación
      def create_invitation_membership(user)
        membership_params = {
          user: user,
          tenant: tenant,
          role: params[:role],
          status: "invited",
          is_primary_admin: false,
          is_default: false,
          created_by: invited_by.id
        }

        membership = TenantMembership.create!(membership_params)
        success(data: membership)
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      # Generar password temporal
      def generate_temporary_password
        SecureRandom.urlsafe_base64(16)
      end

      # Configurar PaperTrail
      def set_paper_trail_context
        PaperTrail.request.whodunnit = invited_by.id
        PaperTrail.request.controller_info = {
          metadata: {
            tenant_id: tenant.id,
            performed_action: "invite_user" }
        }
      end
    end
  end
end
