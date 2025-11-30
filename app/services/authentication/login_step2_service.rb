# app/services/authentication/login_step2_service.rb

module Authentication
  class LoginStep2Service
    include ServiceResultHelper

    attr_reader :session_token, :context_id

    def initialize(session_token:, context_id:)
      @session_token = session_token
      @context_id = context_id
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validar parámetros
      return failure(errors: "Session token is required") if session_token.blank?
      return failure(errors: "Context ID is required") if context_id.blank?

      # Validar session token
      user_result = validate_session_token
      return user_result if user_result.failure?

      user = user_result.data

      # 🔥 Buscar contexto seleccionado por ID
      context_result = find_selected_context(user)
      return context_result if context_result.failure?

      selected_context = context_result.data

      # 🔥 Generar JWT con membership_id incluido
      token_data = JwtEncoder.encode_with_metadata(
        user: user,
        context: selected_context[:context],
        tenant_id: selected_context[:tenant_id],
        membership_id: selected_context[:membership_id]
      )

      # 🔥 Construir respuesta completa
      success(
        data: {
          token: token_data[:token],
          token_type: token_data[:token_type],
          expires_at: token_data[:expires_at],
          expires_in: token_data[:expires_in],
          user: user_data(user),
          active_context: build_active_context(selected_context),
          available_contexts: build_available_contexts(user, selected_context[:id])
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

    # 🔥 Buscar contexto seleccionado por ID
    def find_selected_context(user)
      # Obtener TODOS los contextos disponibles
      available_contexts = AvailableContextsQuery.new(user).call

      # Buscar por context_id
      selected = available_contexts.find { |ctx| ctx[:id] == context_id }

      unless selected
        return failure(
          errors: "Context not available",
          meta: {
            available_context_ids: available_contexts.map { |c| c[:id] },
            message: "Please select from available contexts"
          }
        )
      end

      success(data: selected)
    end

    # Secret para session tokens
    def session_secret
      Rails.application.credentials.dig(:session_secret_key) ||
        ENV.fetch("SESSION_SECRET_KEY", Rails.application.credentials.secret_key_base)
    end

    # 🔥 Construir datos del usuario
    def user_data(user)
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

    # 🔥 Construir contexto activo con toda la información
    def build_active_context(context)
      {
        id: context[:id],
        type: context[:type],
        display_name: context[:display_name],

        # IDs
        membership_id: context[:membership_id],
        tenant_id: context[:tenant_id],

        # Info del tenant (si aplica)
        tenant_name: context[:tenant_name],
        tenant_slug: context[:tenant_slug],
        tenant_status: context[:tenant_status],
        tenant_logo: context[:tenant_logo],

        # Info del rol
        role: context[:role],
        role_name: context[:role_name],

        # Flags
        is_primary_admin: context[:is_primary_admin],
        is_default: context[:is_default],

        # Metadata del tenant
        tenant_trial: context[:tenant_trial],
        tenant_trial_days_remaining: context[:tenant_trial_days_remaining]
      }.compact # Elimina claves con nil
    end

    # 🔥 Lista de contextos disponibles (para switcher)
    def build_available_contexts(user, current_context_id)
      AvailableContextsQuery.new(user).call.map do |ctx|
        {
          id: ctx[:id],
          type: ctx[:type],
          display_name: ctx[:display_name],
          tenant_name: ctx[:tenant_name],
          role_name: ctx[:role_name],
          is_active: ctx[:id] == current_context_id
        }
      end
    end
  end
end
