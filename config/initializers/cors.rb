# ======================================================

# # Configuración de CORS (Cross-Origin Resource Sharing)
# # Permite que frontends en otros dominios puedan consumir nuestra API

# Rails.application.config.middleware.insert_before 0, Rack::Cors do
#   # Configuración para desarrollo
#   if Rails.env.development?
#     allow do
#       # Permitir cualquier origen en desarrollo
#       origins "*"

#       # Recursos de la API
#       resource "/api/*",
#         headers: :any,
#         methods: %i[get post put patch delete options head],
#         credentials: false, # Cambiar a true si usamos cookies
#         max_age: 600 # Cache de preflight requests (10 minutos)
#     end

#     # Permitir acceso a la UI de Swagger
#     allow do
#       origins "*"
#       resource "/apidoc/*",
#         headers: :any,
#         methods: %i[get options],
#         credentials: false
#     end
#   end

#   # Configuración para test
#   if Rails.env.test?
#     allow do
#       origins "*"
#       resource "*",
#         headers: :any,
#         methods: :any,
#         credentials: false
#     end
#   end

#   # Configuración para producción
#   if Rails.env.production?
#     # Lista de orígenes permitidos (cambiar por tus dominios reales)
#     allowed_origins = ENV.fetch("CORS_ALLOWED_ORIGINS", "").split(",").map(&:strip)

#     # Si no hay orígenes configurados, usar un patrón por defecto
#     allowed_origins = [ "https://app.tudominio.com" ] if allowed_origins.empty?

#     allow do
#       origins allowed_origins

#       # Recursos de la API
#       resource "/api/*",
#         headers: :any,
#         methods: %i[get post put patch delete options head],
#         credentials: true, # Permitir envío de cookies/headers de autenticación
#         max_age: 86400, # Cache de 24 horas para preflight
#         expose: %w[Authorization] # Headers expuestos al cliente
#     end

#     # Swagger solo en producción si es necesario (generalmente no se expone)
#     # Descomentar si necesitas Swagger en producción
#     # allow do
#     #   origins allowed_origins
#     #   resource '/apidoc/*',
#     #     headers: :any,
#     #     methods: %i[get options],
#     #     credentials: false
#     # end
#   end
# end

# # Logging de CORS para debugging (solo en desarrollo)
# if Rails.env.development?
#   Rails.application.config.middleware.use(Class.new do
#     def initialize(app)
#       @app = app
#     end

#     def call(env)
#       status, headers, response = @app.call(env)

#       # Log de requests CORS
#       if env["HTTP_ORIGIN"]
#         Rails.logger.debug("[CORS] Origin: #{env['HTTP_ORIGIN']}")
#         Rails.logger.debug("[CORS] Method: #{env['REQUEST_METHOD']}")
#         Rails.logger.debug("[CORS] Response headers: #{headers['Access-Control-Allow-Origin']}")
#       end

#       [ status, headers, response ]
#     end
#   end)
# end
# # =========================================================
#
# frozen_string_literal: true

# Configuración de CORS (Cross-Origin Resource Sharing)
# Acepta cualquier dominio en entornos de prueba y desarrollo.
# Como usas JWT (no cookies), credentials puede estar en false sin problemas.

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  ###############################################
  # ⬛ DESARROLLO (local)
  ###############################################
  if Rails.env.development?
    allow do
      origins "*"

      resource "/api/*",
        headers: :any,
        methods: %i[get post put patch delete options head],
        credentials: false,  # Necesario si origins="*"
        expose: %w[Authorization],
        max_age: 600
    end

    allow do
      origins "*"
      resource "/apidoc/*",
        headers: :any,
        methods: %i[get options],
        credentials: false
    end
  end

  ###############################################
  # ⬛ TEST
  ###############################################
  if Rails.env.test?
    allow do
      origins "*"

      resource "*",
        headers: :any,
        methods: :any,
        credentials: false,
        expose: %w[Authorization]
    end
  end

  ###############################################
  # ⬛ PRODUCCIÓN (MODO PRUEBAS / VERCEL / RENDER)
  ###############################################
  if Rails.env.production?
    # ⚠️ En pruebas queremos permitir TODOS los dominios.
    # Esto evita problemas con Vercel (subdominios dinámicos),
    # Render, Netlify y otras plataformas.
    allow do
      origins "*"

      resource "/api/*",
        headers: :any,
        methods: %i[get post put patch delete options head],
        credentials: false,  # Obligatorio con "*"
        expose: %w[Authorization],
        max_age: 86400
    end
  end
end

###############################################
# LOGGING de CORS en desarrollo
###############################################
if Rails.env.development?
  Rails.application.config.middleware.use(Class.new do
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, response = @app.call(env)

      if env["HTTP_ORIGIN"]
        Rails.logger.debug("[CORS] Origin: #{env['HTTP_ORIGIN']}")
        Rails.logger.debug("[CORS] Method: #{env['REQUEST_METHOD']}")
        Rails.logger.debug("[CORS] Allow-Origin: #{headers['Access-Control-Allow-Origin']}")
      end

      [ status, headers, response ]
    end
  end)
end
