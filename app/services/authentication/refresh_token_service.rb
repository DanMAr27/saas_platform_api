# frozen_string_literal: true

module Authentication
  # Servicio para renovar (refresh) tokens JWT
  # Permite renovar un token antes de que expire sin volver a pedir credenciales
  #
  # Uso:
  #   result = RefreshTokenService.call(token: current_token)
  #
  # Flujo:
  # 1. Validar token actual
  # 2. Revocar token actual
  # 3. Generar nuevo token con el mismo contexto
  # 4. Retornar nuevo token

  class RefreshTokenService
    include ServiceResultHelper

    # Ventana de renovación: permitir renovar si faltan menos de estas horas para expirar
    REFRESH_WINDOW = 2.hours

    attr_reader :token

    def initialize(token:)
      @token = token
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validar parámetros
      return failure(errors: "Token is required") if token.blank?

      # Decodificar y validar token actual
      decode_result = JwtDecoder.decode(token)
      return decode_result if decode_result.failure?

      payload = decode_result.data
      user = decode_result.meta[:user]

      # Validar que el usuario siga activo
      unless user.active?
        return failure(errors: "User account is not active")
      end

      # Verificar si el token está cerca de expirar
      # (opcional: solo permitir refresh si está en ventana de renovación)
      # unless token_in_refresh_window?(payload)
      #   return failure(errors: 'Token is not eligible for refresh yet')
      # end

      # Revocar token actual
      revoke_result = revoke_current_token(payload, user)
      return revoke_result if revoke_result.failure?

      # Generar nuevo token con el mismo contexto
      new_token_data = generate_new_token(user, payload)

      # Retornar nuevo token
      success(
        data: {
          token: new_token_data[:token],
          token_type: new_token_data[:token_type],
          expires_at: new_token_data[:expires_at],
          expires_in: new_token_data[:expires_in],
          user: user_data(user, payload)
        },
        message: "Token refreshed successfully"
      )

    rescue StandardError => e
      Rails.logger.error("[RefreshToken] Error: #{e.class.name} - #{e.message}")
      failure(errors: "Token refresh failed")
    end

    private

    # Verificar si el token está en la ventana de renovación
    def token_in_refresh_window?(payload)
      exp = Time.at(payload[:exp].to_i)
      exp - Time.current <= REFRESH_WINDOW
    end

    # Revocar token actual
    def revoke_current_token(payload, user)
      JwtBlacklist.create!(
        jti: payload[:jti],
        user_id: user.id,
        exp: Time.at(payload[:exp].to_i)
      )

      success(data: { revoked: true })
    rescue ActiveRecord::RecordInvalid => e
      # Si ya existe, continuamos (race condition)
      Rails.logger.warn("[RefreshToken] Token already revoked: #{payload[:jti]}")
      success(data: { revoked: false })
    rescue StandardError => e
      Rails.logger.error("[RefreshToken] Revoke error: #{e.message}")
      failure(errors: "Failed to revoke old token")
    end

    # Generar nuevo token con el mismo contexto
    def generate_new_token(user, old_payload)
      JwtEncoder.encode_with_metadata(
        user: user,
        context: old_payload[:context],
        tenant_id: old_payload[:tenant_id]
      )
    end

    # Construir datos del usuario para respuesta
    def user_data(user, payload)
      {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        full_name: user.full_name,
        avatar_url: user.avatar_url,
        context: payload[:context],
        tenant_id: payload[:tenant_id],
        email_verified: user.email_verified?
      }
    end
  end
end
