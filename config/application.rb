# config/application.rb

require_relative "boot"
# cargar middleware personalizado antes de que se use
require_relative "../app/middleware/tenant_context"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"  # ← NECESARIO para Swagger UI
require "action_cable/engine"

# IMPORTANTE: Agregar Sprockets para assets de Swagger
require "sprockets/railtie"

Bundler.require(*Rails.groups)

module SaasPlatform
  class Application < Rails::Application
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])

    # API-only mode
    config.api_only = true

    # IMPORTANTE: Habilitar assets solo para Swagger
    # Esto permite servir los archivos estáticos de Swagger UI
    config.assets.enabled = true
    config.assets.paths << Rails.root.join("app", "assets", "stylesheets")
    config.assets.paths << Rails.root.join("app", "assets", "javascripts")

    # Solo precompilar assets necesarios para Swagger
    config.assets.precompile += %w[ grape_swagger_rails/application.css grape_swagger_rails/application.js ]

    # Configuración de idioma
    config.i18n.default_locale = :es
    config.i18n.available_locales = [ :en, :es, :ca ]

    # Timezone
    config.time_zone = "Madrid"
    config.active_record.default_timezone = :utc

    # Autoload paths
    config.autoload_paths += %W[
      #{config.root}/app/api
      #{config.root}/app/services
      #{config.root}/app/queries
      #{config.root}/app/policies
      #{config.root}/app/middleware
      #{config.root}/app/validators
      #{config.root}/lib
    ]

    # Eager load paths para producción
    config.eager_load_paths += %W[
      #{config.root}/app/api
      #{config.root}/app/services
      #{config.root}/app/queries
      #{config.root}/app/policies
      #{config.root}/app/middleware
    ]
    # Middleware configuration
    # Agregar TenantContext middleware DESPUÉS de autenticación
    config.middleware.use TenantContext
  end
end
