# app/services/authentication/login_step1_service.rb

module Authentication
  class LoginStep1Service
    include ServiceResultHelper

    attr_reader :email, :password, :request_info

    def initialize(email:, password:, request_info: {})
      @email = email&.strip&.downcase
      @password = password
      @request_info = request_info
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validar parámetros
      return failure(errors: [ "Email is required" ]) if email.blank?
      return failure(errors: [ "Password is required" ]) if password.blank?

      # Buscar usuario
      user = find_user
      unless user
        Rails.logger.info "[LoginStep1] ❌ User not found: #{email}"
        return failure(errors: [ "Invalid credentials" ])
      end

      Rails.logger.info "[LoginStep1] ✓ User found: #{user.email} (ID: #{user.id})"

      # Validar contraseña
      password_valid = user.valid_password?(password)
      Rails.logger.info "[LoginStep1] Password check: #{password_valid ? '✓ VALID' : '❌ INVALID'}"

      unless password_valid
        handle_failed_login(user)
        return failure(errors: [ "Invalid credentials" ])
      end

      # Validar estado del usuario
      validation_result = validate_user_state(user)
      return validation_result if validation_result.failure?

      # 🔥 Obtener contextos disponibles
      contexts_query = AvailableContextsQuery.new(user)
      available_contexts = contexts_query.call

      Rails.logger.info "[LoginStep1] Contexts found: #{available_contexts.size}"
      available_contexts.each_with_index do |ctx, i|
        Rails.logger.info "[LoginStep1]   #{i+1}. #{ctx[:id]} - #{ctx[:display_name]}"
      end

      # Verificar que tenga al menos un contexto
      if available_contexts.empty?
        Rails.logger.info "[LoginStep1] ❌ No contexts available"
        return failure(errors: [ "User has no active contexts or roles" ])
      end

      # Obtener contexto por defecto
      default_context = contexts_query.default_context
      Rails.logger.info "[LoginStep1] Default context: #{default_context&.dig(:display_name) || 'NONE'}"

      # Determinar si requiere selección
      requires_selection = contexts_query.multiple_contexts?

      # Generar session token temporal
      session_token = generate_session_token(user)

      # Actualizar información de login
      update_login_info(user)

      Rails.logger.info "[LoginStep1] ✓ Login successful!"

      # 🔥 Retornar resultado
      success(
        data: {
          requires_context_selection: requires_selection,
          contexts: available_contexts,
          default_context: default_context,
          session_token: session_token,
          user: basic_user_data(user)
        },
        message: "Authentication successful"
      )
    end

    private

    def find_user
      User.find_by_email(email)
    end

    def validate_user_state(user)
      if user.deleted?
        return failure(errors: [ "Account is deactivated" ])
      end

      if user.locked?
        return failure(errors: [ "Account is locked. Please contact support." ])
      end

      unless user.email_verified?
        return failure(
          errors: [ "Email not verified. Please check your inbox." ],
          meta: { requires_verification: true }
        )
      end

      success(data: { valid: true })
    end

    def generate_session_token(user)
      payload = {
        user_id: user.id,
        email: user.email,
        purpose: "context_selection",
        exp: 5.minutes.from_now.to_i,
        iat: Time.current.to_i
      }

      JWT.encode(payload, session_secret, "HS256")
    end

    def session_secret
      Rails.application.credentials.dig(:session_secret_key) ||
        ENV.fetch("SESSION_SECRET_KEY", Rails.application.credentials.secret_key_base)
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

    def basic_user_data(user)
      {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        full_name: user.full_name,
        avatar_url: user.avatar_url,
        email_verified: user.email_verified?
      }
    end
  end
end
