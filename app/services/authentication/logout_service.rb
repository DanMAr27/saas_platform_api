# frozen_string_literal: true

module Authentication
  # Servicio de Logout
  # Revoca un token JWT agregándolo a la blacklist
  #
  # Uso:
  #   result = LogoutService.call(token: token, user: current_user)
  #
  # Flujo:
  # 1. Decodificar token
  # 2. Agregar a blacklist (JwtBlacklist)
  # 3. Retornar confirmación

  class LogoutService
    include ServiceResultHelper

    attr_reader :token, :user

    def initialize(token:, user:)
      @token = token
      @user = user
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validar parámetros
      return failure(errors: "Token is required") if token.blank?
      return failure(errors: "User is required") unless user

      # Decodificar token para obtener payload
      decode_result = JwtDecoder.decode(token)

      # Si el token ya está revocado o es inválido, considerarlo éxito
      # (el usuario ya está deslogueado)
      if decode_result.failure?
        return success(
          data: { revoked: false },
          message: "Already logged out"
        )
      end

      payload = decode_result.data

      # Verificar que el token pertenece al usuario
      unless payload[:sub].to_s == user.id.to_s
        return failure(errors: "Token does not belong to this user")
      end

      # Agregar token a la blacklist
      revoke_result = revoke_token(payload)
      return revoke_result if revoke_result.failure?

      # Retornar éxito
      success(
        data: {
          revoked: true,
          revoked_at: Time.current.iso8601
        },
        message: "Logout successful"
      )

    rescue StandardError => e
      Rails.logger.error("[Logout] Error: #{e.class.name} - #{e.message}")
      failure(errors: "Logout failed")
    end

    private

    # Revocar token agregándolo a la blacklist
    def revoke_token(payload)
      JwtBlacklist.create!(
        jti: payload[:jti],
        user_id: user.id,
        exp: Time.at(payload[:exp].to_i)
      )

      success(data: { revoked: true })
    rescue ActiveRecord::RecordInvalid => e
      # Si ya existe, considerarlo éxito (ya estaba revocado)
      if e.message.include?("Jti has already been taken")
        return success(data: { revoked: false })
      end

      failure(errors: "Failed to revoke token")
    rescue StandardError => e
      Rails.logger.error("[Logout] Revoke error: #{e.message}")
      failure(errors: "Failed to revoke token")
    end
  end
end
