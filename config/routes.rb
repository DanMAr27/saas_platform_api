# config/routes.rb

Rails.application.routes.draw do
  # Define tu root route para redirigir a la documentación de la API
  # root to: redirect("/apidoc")

  # Montar la API de Grape
  # Todas las rutas bajo /api/* serán manejadas por Grape
  mount BaseApi => "/"

  # Montar la UI de Swagger (documentación interactiva)
  # Accesible en: http://localhost:3000/apidoc
  mount GrapeSwaggerRails::Engine => "/apidoc"

  # Redirect /swagger to /apidoc for convenience
  get "/swagger", to: redirect("/apidoc")
  get "/api-docs", to: redirect("/apidoc")

  # Health check route (fuera de la API para monitoreo)
  # Útil para load balancers y herramientas de monitoreo
  get "/health", to: proc {
    [
      200,
      { "Content-Type" => "application/json" },
      [
        {
          status: "ok",
          timestamp: Time.current.iso8601,
          database: ActiveRecord::Base.connection.active?
        }.to_json
      ]
    ]
  }

  # Ruta para mostrar información de la API (opcional)
  get "/api", to: proc {
    [
      200,
      { "Content-Type" => "application/json" },
      [
        {
          name: "SaaS Platform API",
          version: "v1",
          documentation: "#{request.base_url}/apidoc",
          health_check: "#{request.base_url}/health"
        }.to_json
      ]
    ]
  }
end
