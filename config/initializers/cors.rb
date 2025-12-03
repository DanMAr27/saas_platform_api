Rails.application.config.middleware.insert_before 0, Rack::Cors do
  ###############################################
  # DESARROLLO (local)
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
  # TEST
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
  # PRODUCCIÓN (MODO PRUEBAS / VERCEL / RENDER)
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
