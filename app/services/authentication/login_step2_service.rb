# frozen_string_literal: true

module Authentication
  # Servicio de Login - Paso 2: Selección de Contexto
  # Recibe session_token del paso 1 y genera JWT con contexto específico
  #
  # Uso:
  #   result = LoginStep2Service.call(
  #     session_token: 'token_from_step1',
  #     context_type: 'tenant',
  #     tenant_id: 1  # Solo si context_type es 'tenant'
  #   )

  class LoginStep2Service
    include ServiceResultHelper

    attr_reader :session_token, :context_type, :tenant_id

    def initialize(session_token:, context_type:, tenant_id: nil)
      @session_token = session_token
      @context_type = context_type
      @tenant_id = tenant_id
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validar parámetros
      return failure(errors: "Session token is required") if session_token.blank?
      return failure(errors: "Context type is required") if context_type.blank?

      # Validar session token
      user_result = validate_session_token
      return user_result if user_result.failure?

      user = user_result.data

      # Validar contexto seleccionado
      context_result = validate_context_selection(user)
      return context_result if context_result.failure?

      context_data = context_result.data

      # Generar JWT con el contexto seleccionado
      token_data = JwtEncoder.encode_with_metadata(
        user: user,
        context: context_data[:context],
        tenant_id: context_data[:tenant_id]
      )

      # Retornar resultado exitoso
      success(
        data: {
          token: token_data[:token],
          token_type: token_data[:token_type],
          expires_at: token_data[:expires_at],
          expires_in: token_data[:expires_in],
          user: user_data(user, context_data)
        },
        message: "Context selected successfully"
      )
    end

    private

    # Validar y decodificar session token
    def validate_session_token
      begin
        payload = JWT.decode(
          session_token,
          session_secret,
          true,
          { algorithm: "HS256", verify_expiration: true }
        ).first

        # Verificar que es un token de selección de contexto
        unless payload["purpose"] == "context_selection"
          return failure(errors: "Invalid session token")
        end

        # Buscar usuario
        user = User.find_by(id: payload["user_id"])
        unless user&.active?
          return failure(errors: "User not found or inactive")
        end

        success(data: user)

      rescue JWT::ExpiredSignature
        failure(errors: "Session expired. Please login again.")
      rescue JWT::DecodeError => e
        Rails.logger.error("[LoginStep2] Invalid session token: #{e.message}")
        failure(errors: "Invalid session token")
      end
    end

    # Validar que el contexto seleccionado sea válido para el usuario
    def validate_context_selection(user)
      # Obtener contextos disponibles
      available_contexts = AvailableContextsQuery.new(user).call

      # Buscar el contexto seleccionado
      selected_context = case context_type
      when "platform"
                          find_platform_context(available_contexts)
      when "tenant"
                          find_tenant_context(available_contexts)
      else
                          return failure(errors: "Invalid context type: #{context_type}")
      end

      unless selected_context
        return failure(errors: "Selected context is not available for this user")
      end

      # Retornar datos del contexto
      success(
        data: {
          context: selected_context[:context],
          tenant_id: selected_context[:tenant_id],
          role: selected_context[:role],
          role_name: selected_context[:role_name],
          full_context: selected_context
        }
      )
    end

    # Encontrar contexto platform
    def find_platform_context(available_contexts)
      available_contexts.find { |ctx| ctx[:type] == "platform" }
    end

    # Encontrar contexto tenant específico
    def find_tenant_context(available_contexts)
      return nil if tenant_id.blank?

      available_contexts.find do |ctx|
        ctx[:type] == "tenant" && ctx[:tenant_id] == tenant_id.to_i
      end
    end

    # Secret para session tokens
    def session_secret
      Rails.application.credentials.dig(:session_secret_key) ||
        ENV.fetch("SESSION_SECRET_KEY", Rails.application.credentials.secret_key_base)
    end

    # Construir datos del usuario para respuesta
    def user_data(user, context_data)
      {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        full_name: user.full_name,
        avatar_url: user.avatar_url,
        email_verified: user.email_verified?,
        context: context_data[:context],
        tenant_id: context_data[:tenant_id],
        role: context_data[:role],
        role_name: context_data[:role_name]
      }
    end
  end
end
