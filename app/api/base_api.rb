# app/api/base_api.rb

# API Base - Configuración global para todas las APIs
# Todas las APIs heredarán de esta clase para compartir configuración común

class BaseApi < Grape::API
  # Prefijo base para todas las rutas de la API
  prefix :api

  # Formato de respuesta por defecto
  format :json
  formatter :json, Grape::Formatter::Json

  # Content-type por defecto
  content_type :json, "application/json"

  # Configuración de errores predeterminados
  default_format :json

  # Helpers globales disponibles en todos los endpoints
  helpers do
    # Respuesta de error consistente para la API
    # RENOMBRADO de error_response a api_error para evitar conflicto con Grape internals
    def api_error(message:, status:, errors: nil)
      response = {
        success: false,
        error: {
          message: message,
          status: status
        }
      }

      response[:error][:details] = errors if errors.present?
      response[:error][:timestamp] = Time.current.iso8601

      error!(response, status)
    end

    # Formato de respuesta exitosa consistente
    def success_response(data: nil, message: nil, meta: nil)
      response = {
        success: true,
        data: data
      }

      response[:message] = message if message.present?
      response[:meta] = meta if meta.present?
      response[:timestamp] = Time.current.iso8601

      response
    end

    # Método para logging de requests
    def log_request
      Rails.logger.info("[API] #{request.request_method} #{request.path}")
      Rails.logger.debug("[API] Params: #{params.inspect}") if Rails.env.development?
    end
  end

  # ===========================================================================
  # MANEJO DE ERRORES
  # ===========================================================================
  # IMPORTANTE: No usar rescue_from :all porque captura también los errores
  # intencionales lanzados por error!() causando loops infinitos
  # ===========================================================================

  # Errores de validación de Grape
  rescue_from Grape::Exceptions::ValidationErrors do |e|
    Rails.logger.error("Validation Error: #{e.message}")

    error!({
      success: false,
      error: {
        message: "Validation failed",
        status: 422,
        details: e.full_messages,
        timestamp: Time.current.iso8601
      }
    }, 422)
  end

  # Registro no encontrado
  rescue_from ActiveRecord::RecordNotFound do |e|
    Rails.logger.error("Record Not Found: #{e.message}")

    error!({
      success: false,
      error: {
        message: "Resource not found",
        status: 404,
        timestamp: Time.current.iso8601
      }
    }, 404)
  end

  # Validaciones de ActiveRecord fallidas
  rescue_from ActiveRecord::RecordInvalid do |e|
    Rails.logger.error("Record Invalid: #{e.message}")

    error!({
      success: false,
      error: {
        message: "Validation failed",
        status: 422,
        details: e.record.errors.full_messages,
        timestamp: Time.current.iso8601
      }
    }, 422)
  end

  # Error de autorización (Pundit)
  rescue_from Pundit::NotAuthorizedError do |e|
    Rails.logger.error("Authorization Error: #{e.message}")

    error!({
      success: false,
      error: {
        message: "You are not authorized to perform this action",
        status: 403,
        timestamp: Time.current.iso8601
      }
    }, 403)
  end

  # Error de tenant no configurado
  rescue_from ActsAsTenant::Errors::NoTenantSet do |e|
    Rails.logger.error("Tenant Error: #{e.message}")

    error!({
      success: false,
      error: {
        message: "Tenant context is required for this operation",
        status: 400,
        timestamp: Time.current.iso8601
      }
    }, 400)
  end

  # Errores genéricos (último recurso)
  rescue_from StandardError do |e|
    Rails.logger.error("Unhandled Error: #{e.class.name} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?

    error!({
      success: false,
      error: {
        message: Rails.env.production? ? "Internal server error" : e.message,
        status: 500,
        details: Rails.env.production? ? nil : [ e.class.name ],
        timestamp: Time.current.iso8601
      }
    }, 500)
  end

  # Hook antes de cada request
  before do
    log_request
    header "X-API-Version", "v1"
    header "X-Request-ID", request.env["action_dispatch.request_id"] || SecureRandom.uuid
  end

  # Hook después de cada request
  after do
    # Aquí podríamos agregar métricas, logging adicional, etc.
  end

  # Montar las versiones de la API
  mount V1::Base
end
