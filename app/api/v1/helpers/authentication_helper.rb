# app/api/v1/helpers/authentication_helper.rb

module V1
  module Helpers
    module AuthenticationHelper
      # Obtener el usuario actual del token JWT
      # @return [User, nil]
      def current_user
        return @current_user if defined?(@current_user)

        token = extract_token
        return nil unless token

        result = Authentication::JwtDecoder.decode(token)

        if result.success?
          @current_user = result.meta[:user]
          @current_payload = result.data

          # 🔥 ESTABLECER TENANT SEGÚN CONTEXTO
          setup_tenant_context!
        else
          @current_user = nil
          @current_payload = nil
          ActsAsTenant.current_tenant = nil
        end

        @current_user
      end

      # Obtener el payload del token JWT actual
      # @return [Hash, nil]
      def current_payload
        current_user # Esto inicializa @current_payload
        @current_payload
      end

      # Verificar si hay un usuario autenticado
      # @return [Boolean]
      def authenticated?
        current_user.present?
      end

      # Forzar autenticación (lanzar error si no está autenticado)
      def authenticate!
        return if authenticated?

        error!({
          success: false,
          error: {
            message: "Authentication required",
            status: 401,
            timestamp: Time.current.iso8601
          }
        }, 401)
      end

      # Obtener el contexto del usuario actual (platform o tenant)
      # @return [String, nil]
      def current_context
        current_payload&.dig(:context)
      end

      # Obtener el tenant_id del contexto actual
      # @return [Integer, nil]
      def current_tenant_id
        current_payload&.dig(:tenant_id)
      end

      # Verificar si el usuario tiene contexto de plataforma
      # @return [Boolean]
      def platform_context?
        current_context == "platform"
      end

      # Verificar si el usuario tiene contexto de tenant
      # @return [Boolean]
      def tenant_context?
        current_context == "tenant"
      end

      # Información del request para auditoría
      # @return [Hash]
      def request_info
        {
          ip: request.ip,
          user_agent: request.user_agent,
          method: request.request_method,
          path: request.path,
          referer: request.referer
        }
      end

      # Obtener ID del request para tracking
      # @return [String]
      def request_id
        request.env["action_dispatch.request_id"] || SecureRandom.uuid
      end

      private

      # Extraer token del header Authorization
      # Formato esperado: "Bearer {token}"
      # @return [String, nil]
      def extract_token
        auth_header = headers["Authorization"] || headers["authorization"]
        return nil unless auth_header

        # Formato: "Bearer {token}"
        match = auth_header.match(/^Bearer\s+(.+)$/i)
        match ? match[1] : nil
      end

      # Establecer el tenant context según el JWT
      def setup_tenant_context!
        context = @current_payload[:context]

        case context
        when "platform"
          # Contexto de plataforma: NO establecer tenant
          # Platform admins operan sin tenant context por defecto
          ActsAsTenant.current_tenant = nil

        when "tenant"
          # Contexto de tenant: establecer el tenant del JWT
          tenant_id = @current_payload[:tenant_id]

          if tenant_id.present?
            tenant = ::Tenant.find_by(id: tenant_id)
            ActsAsTenant.current_tenant = tenant if tenant
          else
            # Token de tenant sin tenant_id es inválido
            ActsAsTenant.current_tenant = nil
          end

        else
          # Contexto desconocido
          ActsAsTenant.current_tenant = nil
        end
      end
    end
  end
end
