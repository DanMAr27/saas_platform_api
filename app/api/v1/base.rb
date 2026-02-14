# app/api/v1/base.rb

module V1
  # Base de la versión 1 de la API
  # Aquí se montan todos los endpoints específicos de v1
  class Base < Grape::API
    version "v1", using: :path

    # ============================================
    # ENDPOINTS SIN CONTEXTO (públicos/autenticación)
    # ============================================
    mount V1::AuthenticationApi

    # ============================================
    # ENDPOINTS DE PLATAFORMA (SuperAdmin)
    # ============================================
    mount V1::Platform::TenantsApi
    mount V1::Platform::UsersApi

    # ============================================
    # ENDPOINTS DE MANAGEMENT (contexto tenant)
    # ============================================
    mount V1::Management::ProfileApi
    mount V1::Management::TenantsApi
    mount V1::Management::OrganizationalNodesApi
    mount V1::Management::OrganizationalLevelsApi

    mount V1::Management::SelectorsApi
    mount V1::Management::UserRefScopesApi
    mount V1::Management::VehiclesApi
    mount V1::Management::ScopesApi
    mount V1::Management::UsersApi
    mount V1::Management::RolesApi

    # ============================================
    # ENDPOINTS DE DRIVER (contexto driver)
    # ============================================
    mount V1::Driver::ProfileApi

    # ============================================
    # ENDPOINTS DE WORKSHOP (contexto workshop)
    # ============================================
    mount V1::Workshop::ProfileApi


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
      # Tags para agrupar endpoints por portal
      tags: [
        # ============================================
        # AUTHENTICATION (Sin Contexto)
        # ============================================
        {
          name: "Authentication - Login",
          description: "Login de usuarios y selección de contexto"
        },
        {
          name: "Authentication - Tokens",
          description: "Gestión de tokens JWT (refresh, validate, logout)"
        },
        {
          name: "Authentication - User Info",
          description: "Información del usuario actual y contextos disponibles"
        },
        {
          name: "Authentication - Context Switch",
          description: "Cambio de contexto entre tenants"
        },

        # ============================================
        # PLATFORM ADMINISTRATION (SuperAdmin)
        # ============================================
        {
          name: "Platform - Tenants",
          description: "Gestión de tenants (solo SuperAdmin)"
        },
        {
          name: "Platform - Statistics",
          description: "Métricas y estadísticas de la plataforma (solo SuperAdmin)"
        },
        {
          name: "Platform - Roles",
          description: "Vista de roles del sistema (solo lectura, SuperAdmin)"
        },
        {
          name: "Platform - Impersonation",
          description: "Suplantación de usuarios para soporte (solo Support Admin)"
        },

        # ============================================
        # MANAGEMENT (Tenant Admin/Manager)
        # ============================================
        {
          name: "Management - Profile",
          description: "Perfil del usuario en contexto tenant"
        },
        {
          name: "Management - Users",
          description: "Gestión de usuarios del tenant"
        },
        {
          name: "Management - Roles",
          description: "Asignación de roles dentro del tenant"
        },
        {
          name: "Management - Scopes",
          description: "Gestión de scopes (node/vehicle)"
        },
        {
          name: "Management - Vehicles",
          description: "Gestión de vehículos del tenant"
        },
        {
          name: "Management - Organizational Levels",
          description: "Niveles de la estructura organizacional"
        },
        {
          name: "Management - Organizational Nodes",
          description: "Nodos de la estructura organizacional"
        },
        {
          name: "Management - Organizational Tree",
          description: "Árbol completo de la organización"
        },
        {
          name: "Management - Selectors",
          description: "Endpoints ligeros para alimentar componentes UI tipo select/dropdown"
        },
        {
          name: "Management - User Scopes",
          description: "Gestión de scopes de usuarios específicos"
        },

        # ============================================
        # DRIVER (Conductores)
        # ============================================
        {
          name: "Driver - Profile",
          description: "Perfil y configuración del conductor"
        },

        # ============================================
        # WORKSHOP (Talleres)
        # ============================================
        {
          name: "Workshop - Profile",
          description: "Perfil y configuración del taller"
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
