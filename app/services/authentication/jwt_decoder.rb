# frozen_string_literal: true

module Authentication
  # Servicio para decodificar y validar tokens JWT
  # Considera multi-contexto y usuarios sin tenant (platform/support)
  class JwtDecoder
    include ServiceResultHelper

    ALGORITHM = "HS256"

    class << self
      def decode(token)
        new.decode(token)
      end

      def decode_unverified(token)
        new.decode_unverified(token)
      end

      def peek(token)
        new.peek(token)
      end

      def expired?(token)
        new.expired?(token)
      end

      def extract_user_id(token)
        new.extract_user_id(token)
      end
    end

    # Decodifica token con verificación completa
    def decode(token)
      return failure(errors: "Token is missing") if token.blank?

      payload, header = JWT.decode(
        token,
        secret_key,
        true,
        {
          algorithm: ALGORITHM,
          verify_expiration: true,
          verify_iat: true,
          iss: jwt_issuer,
          aud: jwt_audience,
          verify_iss: true,
          verify_aud: true
        }
      )

      if token_revoked?(payload)
        return failure(errors: "Token has been revoked")
      end

      user = User.find_by(id: payload["sub"])
      unless user&.active?
        return failure(errors: "User not found or inactive")
      end

      # Validar tenant_id solo si el contexto es tenant
      if payload["context"] == "tenant" && payload["tenant_id"].present?
        tenant_membership = TenantMembership.active.find_by(user_id: user.id, tenant_id: payload["tenant_id"])
        unless tenant_membership
          return failure(errors: "Access denied to this tenant")
        end
      end

      success(data: payload.with_indifferent_access, meta: { header: header, user: user })
    rescue JWT::ExpiredSignature
      failure(errors: "Token has expired")
    rescue JWT::InvalidIssuerError
      failure(errors: "Token issuer is invalid")
    rescue JWT::InvalidAudError
      failure(errors: "Token audience is invalid")
    rescue JWT::DecodeError => e
      Rails.logger.error("[JWT] Decode error: #{e.message}")
      failure(errors: "Invalid token")
    rescue StandardError => e
      Rails.logger.error("[JWT] Unexpected error: #{e.class.name} - #{e.message}")
      failure(errors: "Token validation failed")
    end

    # Decodifica sin verificar (debugging)
    def decode_unverified(token)
      payload, header = JWT.decode(token, nil, false)
      { payload: payload.with_indifferent_access, header: header }
    rescue JWT::DecodeError => e
      Rails.logger.error("[JWT] Decode error: #{e.message}")
      nil
    end

    # Extraer info básica sin verificar completamente
    def peek(token)
      decoded = decode_unverified(token)
      return nil unless decoded

      {
        user_id: decoded[:payload][:sub],
        email: decoded[:payload][:email],
        context: decoded[:payload][:context],
        tenant_id: decoded[:payload][:tenant_id],
        expires_at: Time.at(decoded[:payload][:exp].to_i),
        issued_at: Time.at(decoded[:payload][:iat].to_i),
        jti: decoded[:payload][:jti]
      }
    end

    def expired?(token)
      info = peek(token)
      return true unless info
      info[:expires_at] < Time.current
    end

    def extract_user_id(token)
      info = peek(token)
      info&.dig(:user_id)
    end

    private

    def token_revoked?(payload)
      jti = payload["jti"]
      return false unless jti.present?
      JwtBlacklist.exists?(jti: jti)
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
