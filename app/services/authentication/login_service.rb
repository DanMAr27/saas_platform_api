# frozen_string_literal: true

module Authentication
  # Servicio de Login
  # Autentica un usuario y determina automáticamente su contexto
  # basándose en sus memberships
  #
  # Flujo:
  # 1. Validar credenciales
  # 2. Obtener contextos disponibles del usuario
  # 3. Si tiene UN solo contexto → generar token automáticamente
  # 4. Si tiene MÚLTIPLES contextos → retornar lista para que seleccione
  # 5. Si se proporciona contexto específico → validar y generar token

  class LoginService
    include ServiceResultHelper

    attr_reader :email, :password, :context, :tenant_id, :request_info

    def initialize(email:, password:, context: nil, tenant_id: nil, request_info: {})
      @email = email&.strip&.downcase
      @password = password
      @context = context
      @tenant_id = tenant_id
      @request_info = request_info
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validar parámetros básicos
      return failure(errors: "Email is required") if email.blank?
      return failure(errors: "Password is required") if password.blank?

      # Buscar usuario
      user = find_user
      return failure(errors: "Invalid credentials") unless user

      # Validar contraseña
      unless user.valid_password?(password)
        handle_failed_login(user)
        return failure(errors: "Invalid credentials")
      end

      # Validar estado del usuario
      validation_result = validate_user_state(user)
      return validation_result if validation_result.failure?

      # Obtener contextos disponibles
      available_contexts = get_available_contexts(user)

      if available_contexts.empty?
        return failure(errors: "No access granted. Please contact support.")
      end

      # Si se proporciona un contexto específico, validarlo y generar token
      if context.present?
        return generate_token_for_context(user, available_contexts)
      end

      # Si tiene UN solo contexto, generar token automáticamente
      if available_contexts.size == 1
        selected_context = available_contexts.first
        return generate_token_direct(user, selected_context)
      end

      # Si tiene MÚLTIPLES contextos, retornar lista para selección
      success(
        data: {
          requires_context_selection: true,
          available_contexts: format_contexts_for_selection(available_contexts)
        },
        message: "Multiple contexts available"
      )
    end

    private

    def find_user
      User.find_by_email(email)
    end

    def validate_user_state(user)
      if user.deleted?
        return failure(errors: "Account is deactivated")
      end

      if user.locked?
        return failure(errors: "Account is locked. Please contact support.")
      end

      unless user.email_verified?
        return failure(
          errors: "Email not verified. Please check your inbox.",
          meta: { requires_verification: true }
        )
      end

      success(data: { valid: true })
    end

    # Obtener todos los contextos disponibles para el usuario
    def get_available_contexts(user)
      contexts = []

      # Verificar si tiene platform membership
      if user.respond_to?(:platform_membership) && user.platform_membership.present?
        contexts << {
          type: "platform",
          role: user.platform_membership.role.slug,
          tenant_id: nil
        }
      end

      # Obtener tenant memberships activas
      if user.respond_to?(:tenant_memberships)
        user.tenant_memberships.active.includes(:tenant, :role).each do |membership|
          contexts << {
            type: "tenant",
            tenant_id: membership.tenant_id,
            tenant_name: membership.tenant.name,
            tenant_slug: membership.tenant.slug,
            role: membership.role.slug,
            is_primary_admin: membership.is_primary_admin?
          }
        end
      end

      contexts
    end

    # Generar token directamente cuando hay un solo contexto
    def generate_token_direct(user, context_data)
      token_data = JwtEncoder.encode_with_metadata(
        user: user,
        context: context_data[:type],
        tenant_id: context_data[:tenant_id]
      )

      update_login_info(user)

      success(
        data: {
          token: token_data[:token],
          token_type: token_data[:token_type],
          expires_at: token_data[:expires_at],
          expires_in: token_data[:expires_in],
          user: user_data(user, context_data)
        },
        message: "Login successful"
      )
    end

    # Generar token para un contexto específico seleccionado
    def generate_token_for_context(user, available_contexts)
      # Buscar el contexto seleccionado
      selected = find_selected_context(available_contexts)

      unless selected
        return failure(
          errors: "Invalid context or access denied",
          meta: {
            available_contexts: format_contexts_for_selection(available_contexts)
          }
        )
      end

      generate_token_direct(user, selected)
    end

    # Buscar el contexto seleccionado en los disponibles
    def find_selected_context(available_contexts)
      if context == "platform"
        available_contexts.find { |c| c[:type] == "platform" }
      elsif context == "tenant"
        if tenant_id.blank?
          return nil
        end
        available_contexts.find do |c|
          c[:type] == "tenant" && c[:tenant_id] == tenant_id.to_i
        end
      else
        nil
      end
    end

    # Formatear contextos para la respuesta de selección
    def format_contexts_for_selection(contexts)
      contexts.map do |ctx|
        if ctx[:type] == "platform"
          {
            type: "platform",
            role: ctx[:role],
            display_name: "Platform #{ctx[:role].titleize}"
          }
        else
          {
            type: "tenant",
            tenant_id: ctx[:tenant_id],
            tenant_name: ctx[:tenant_name],
            tenant_slug: ctx[:tenant_slug],
            role: ctx[:role],
            is_primary_admin: ctx[:is_primary_admin],
            display_name: "#{ctx[:tenant_name]} (#{ctx[:role].titleize})"
          }
        end
      end
    end

    def update_login_info(user)
      user.update_columns(
        last_login_at: Time.current,
        sign_in_count: user.sign_in_count + 1,
        current_sign_in_at: Time.current,
        last_sign_in_at: user.current_sign_in_at || Time.current,
        current_sign_in_ip: request_info[:ip],
        last_sign_in_ip: user.current_sign_in_ip,
        failed_attempts: 0
      )
    end

    def handle_failed_login(user)
      user.increment!(:failed_attempts)

      if user.failed_attempts >= Devise.maximum_attempts
        user.lock_access!
        Rails.logger.warn("[Login] Account locked for user #{user.email}")
      end
    end

    def user_data(user, context_data)
      base_data = {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        full_name: user.full_name,
        avatar_url: user.avatar_url,
        context: context_data[:type],
        email_verified: user.email_verified?
      }

      if context_data[:type] == "tenant"
        base_data.merge!(
          tenant_id: context_data[:tenant_id],
          tenant_name: context_data[:tenant_name],
          tenant_slug: context_data[:tenant_slug],
          role: context_data[:role],
          is_primary_admin: context_data[:is_primary_admin]
        )
      else
        base_data.merge!(
          tenant_id: nil,
          role: context_data[:role]
        )
      end

      base_data
    end
  end
end
