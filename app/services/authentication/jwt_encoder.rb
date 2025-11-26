# frozen_string_literal: true

module Authentication
  # Servicio para codificar tokens JWT
  # Genera tokens con información de usuario y contexto (platform/tenant)
  class JwtEncoder
    include ServiceResultHelper

    ALGORITHM = "HS256"
    DEFAULT_EXPIRATION = 24.hours.to_i

    class << self
      # Genera JWT para un usuario en un contexto específico
      # @param user [User]
      # @param context [String] 'platform', 'tenant', 'external_org'
      # @param tenant_id [Integer, nil] solo para contextos tenant
      # @param expiration [Integer, nil] segundos
      def encode(user:, context:, tenant_id: nil, expiration: nil)
        exp = expiration || DEFAULT_EXPIRATION
        jti = generate_jti
        payload = build_payload(user: user, context: context, tenant_id: tenant_id, jti: jti, exp: exp)
        JWT.encode(payload, secret_key, ALGORITHM)
      end

      # Genera JWT y retorna metadata
      def encode_with_metadata(user:, context:, tenant_id: nil, expiration: nil)
        exp = expiration || DEFAULT_EXPIRATION
        issued_at = Time.current
        expires_at = issued_at + exp

        token = encode(user: user, context: context, tenant_id: tenant_id, expiration: exp)

        {
          token: token,
          expires_at: expires_at.iso8601,
          issued_at: issued_at.iso8601,
          expires_in: exp,
          token_type: "Bearer"
        }
      end

      private

      def build_payload(user:, context:, tenant_id:, jti:, exp:)
        issued_at = Time.current.to_i
        payload = {
          jti: jti,
          sub: user.id.to_s,
          iat: issued_at,
          exp: issued_at + exp,
          iss: jwt_issuer,
          aud: jwt_audience,
          email: user.email,
          name: user.full_name,
          verified: user.email_verified?,
          context: context
        }

        # Agregar tenant_id solo si aplica
        payload[:tenant_id] = tenant_id if context == "tenant" && tenant_id.present?
        payload
      end

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
