# app/api/v1/base.rb

module V1
  # Base de la versión 1 de la API
  # Aquí se montan todos los endpoints específicos de v1
  class Base < Grape::API
    version "v1", using: :path

    # Montar endpoints de autenticación (disponible sin contexto)
    mount V1::AuthenticationApi
    mount V1::Tenant::ProfileApi
    mount V1::Platform::TenantsApi

    # Endpoint de health check (siempre disponible, sin autenticación)
    desc "Health check endpoint"
    get :health do
      {
        status: "ok",
        version: "v1",
        timestamp: Time.current.iso8601,
        environment: Rails.env,
        database: ActiveRecord::Base.connection.active? ? "connected" : "disconnected"
      }
    end

    # Documentación con Swagger
    add_swagger_documentation(
      api_version: "v1",
      doc_version: "1.0.0",
      info: {
        title: "SaaS Platform API",
        description: "API Documentation for SaaS Platform with multitenancy support",
        contact: {
          name: "API Support",
          email: ENV.fetch("API_SUPPORT_EMAIL", "support@saasplatform.com"),
          url: ENV.fetch("API_SUPPORT_URL", "https://saasplatform.com/support")
        },
        license: {
          name: "Proprietary",
          url: "https://saasplatform.com/license"
        }
      },
      # Configuración de seguridad (JWT Bearer Token)
      security_definitions: {
        bearer_token: {
          type: "apiKey",
          name: "Authorization",
          in: "header",
          description: "JWT Bearer Token. Format: Bearer {token}"
        }
      },
      security: [
        { bearer_token: [] }
      ],
      # Configuración de host y schemes
      host: ENV.fetch("API_HOST", "localhost:3000"),
      schemes: Rails.env.production? ? [ "https" ] : [ "http" ],
      base_path: "/api",
      mount_path: "/swagger_doc",
      # Configuración de modelos y arrays
      array_use_braces: true,
      # Tags para agrupar endpoints
      tags: [
        {
          name: "Authentication",
          description: "Login, logout, and token management"
        },
        {
          name: "Platform",
          description: "Platform administration (SuperAdmin only)"
        },
        {
          name: "Tenant",
          description: "Tenant-scoped operations"
        },
        {
          name: "Users",
          description: "User management"
        },
        {
          name: "Roles",
          description: "Role assignment and management"
        }
      ],
      # Formato de respuestas
      format: :json,
      # Ocultar endpoints internos
      hide_format: true,
      hide_documentation_path: false,
      # Configuración adicional
      produces: [ "application/json" ],
      consumes: [ "application/json" ]
    )
  end
end
