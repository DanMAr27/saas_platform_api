# app/middleware/tenant_context.rb
# Middleware para establecer el contexto de tenant en cada request
# MODIFICADO para soportar usuarios platform sin tenant_id

class TenantContext
  def initialize(app)
    @app = app
  end

  def call(env)
    # Obtener tenant_id del token JWT
    tenant_id = extract_tenant_id_from_token(env)
    context = extract_context_from_token(env)

    # Si el contexto es platform, ejecutar sin tenant
    if context == "platform"
      ActsAsTenant.without_tenant do
        @app.call(env)
      end
    elsif tenant_id.present?
      # Contexto tenant normal
      tenant = Tenant.find_by(id: tenant_id)

      if tenant&.active?
        # Establecer contexto de tenant para este request
        ActsAsTenant.with_tenant(tenant) do
          @app.call(env)
        end
      else
        # Tenant no encontrado o inactivo
        error_response(
          "Invalid or inactive tenant",
          401,
          env
        )
      end
    else
      # Sin tenant_id y sin contexto platform (puede ser endpoint público)
      # Ejecutar sin tenant context
      ActsAsTenant.without_tenant do
        @app.call(env)
      end
    end
  rescue ActsAsTenant::Errors::NoTenantSet => e
    Rails.logger.error("[TenantContext] No tenant set: #{e.message}")
    error_response("Tenant context required", 400, env)
  rescue StandardError => e
    Rails.logger.error("[TenantContext] Error: #{e.class.name} - #{e.message}")
    error_response("Tenant context error", 500, env)
  end

  private

  # Extraer tenant_id del token JWT
  def extract_tenant_id_from_token(env)
    payload = extract_payload(env)
    payload&.dig(:tenant_id)
  end

  # Extraer context del token JWT
  def extract_context_from_token(env)
    payload = extract_payload(env)
    payload&.dig(:context)
  end

  # Extraer payload completo del token
  def extract_payload(env)
    auth_header = env["HTTP_AUTHORIZATION"]
    return nil unless auth_header

    match = auth_header.match(/^Bearer\s+(.+)$/i)
    return nil unless match

    token = match[1]
    Authentication::JwtDecoder.peek(token)
  rescue StandardError => e
    Rails.logger.debug("[TenantContext] Failed to extract payload: #{e.message}")
    nil
  end

  # Respuesta de error
  def error_response(message, status, env)
    body = {
      success: false,
      error: {
        message: message,
        status: status,
        timestamp: Time.current.iso8601
      }
    }.to_json

    headers = {
      "Content-Type" => "application/json",
      "Content-Length" => body.bytesize.to_s
    }

    [ status, headers, [ body ] ]
  end
end
