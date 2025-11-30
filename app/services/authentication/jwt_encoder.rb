# app/services/authentication/jwt_encoder.rb

module Authentication
  class JwtEncoder
    include ServiceResultHelper

    ALGORITHM = "HS256"
    DEFAULT_EXPIRATION = 24.hours.to_i

    class << self
      # 🔥 Método simplificado - Token ligero
      def encode_with_metadata(user:, context:, tenant_id: nil, membership_id: nil, expiration: nil)
        exp = expiration || DEFAULT_EXPIRATION
        issued_at = Time.current
        expires_at = issued_at + exp
        jti = generate_jti

        # 🔥 Payload ligero
        payload = {
          jti: jti,
          sub: user.id.to_s,
          iat: issued_at.to_i,
          exp: expires_at.to_i,
          iss: jwt_issuer,
          aud: jwt_audience,

          # Datos básicos del usuario
          email: user.email,
          name: user.full_name,
          verified: user.email_verified?,

          # Contexto
          context: context,
          tenant_id: tenant_id,           # nil para platform
          membership_id: membership_id    # 🔥 NUEVO: Identificar membresía activa
        }

        # Codificar token
        token = JWT.encode(payload, secret_key, ALGORITHM)

        # Retornar con metadata
        {
          token: token,
          token_type: "Bearer",
          expires_at: expires_at.iso8601,
          expires_in: exp,
          issued_at: issued_at.iso8601
        }
      end

      private

      def generate_jti
        SecureRandom.uuid
      end

      def secret_key
        Rails.application.credentials.dig(:devise_jwt_secret_key) ||
          ENV.fetch("DEVISE_JWT_SECRET_KEY") ||
          Rails.application.credentials.secret_key_base
      end

      def jwt_issuer
        ENV.fetch("JWT_ISSUER", "saas_platform")
      end

      def jwt_audience
        ENV.fetch("JWT_AUDIENCE", "saas_platform_api")
      end
    end
  end
end
