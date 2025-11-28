# frozen_string_literal: true

# Configuración de Grape Swagger Rails para la UI de Swagger
# Esto monta la interfaz visual para explorar y probar la API

GrapeSwaggerRails.options.tap do |config|
  # URL donde se encuentra la especificación Swagger (generada por grape-swagger)
  config.url = "/api/v1/swagger_doc"

  # Título que aparecerá en la UI
  config.app_name = "SaaS Platform API"

  # Versión de la API
  config.app_url = ENV.fetch("API_BASE_URL", "http://localhost:3000")

  # Configuración de la interfaz Swagger UI
  config.doc_expansion = "list" # Opciones: 'none', 'list', 'full'

  # Headers que se incluirán en todas las peticiones de prueba
  config.headers = {
    "Content-Type" => "application/json",
    "Accept" => "application/json"
  }

  # Configuración de autorización JWT
  # Esto permite que los usuarios ingresen su token JWT en la UI
  config.api_auth = "bearer" # Autenticación tipo Bearer Token
  config.api_key_name = "Authorization"
  config.api_key_type = "header"

  # Ocultar modelos en la documentación (opcional)
  config.hide_url_input = false

  # Habilitar validación de respuestas
  config.validator_url = nil # Cambiar si tienes un validador personalizado
end

# Configuración de rutas para la UI de Swagger
# IMPORTANTE: Como es API-only, necesitamos montar los assets de Swagger manualmente
Rails.application.config.assets.enabled = true if Rails.env.development?
Rails.application.config.assets.paths << Rails.root.join("node_modules") if Rails.env.development?

# Precompilación de assets para producción (si es necesario)
if Rails.env.production?
  Rails.application.config.assets.precompile += %w[
    grape_swagger_rails/application.css
    grape_swagger_rails/application.js
  ]
end
