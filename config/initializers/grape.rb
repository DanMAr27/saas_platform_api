# config/initializers/grape.rb

# Configuración de formato de respuesta
Grape::Entity.format_with :iso_timestamp do |date|
  date.iso8601 if date.present?
end

# Configuración de logging para desarrollo
if Rails.env.development?
  # En desarrollo, registramos todas las peticiones
  Grape::Endpoint.before_each do |endpoint|
    Rails.logger.info "[GRAPE] #{endpoint.request.request_method} #{endpoint.request.path}"
    Rails.logger.debug "[GRAPE] Params: #{endpoint.params.inspect}" if endpoint.params.any?
  end
end

# Configuración de parsers personalizados
# Grape automáticamente parsea JSON, pero podemos extenderlo
Grape::Middleware::Base.module_eval do
  def content_types
    {
      json: "application/json",
      xml: "application/xml",
      txt: "text/plain"
    }
  end
end

# NOTA IMPORTANTE:
# NO sobrescribimos Grape::Middleware::Error porque interfiere con el manejo
# normal de errores de Grape. El manejo de errores debe hacerse en BaseApi
# usando rescue_from :all
