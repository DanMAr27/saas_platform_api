source "https://rubygems.org"

# ruby "3.3.0" # O la versión de Ruby que estés usando

# Core Rails
gem "rails", "~> 8.0.3"
gem "pg", "~> 1.5" # PostgreSQL adapter

# Servidor de aplicación
gem "puma", ">= 5.0"

# Timezone data para Windows
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Performance
gem "bootsnap", require: false

# ============================================
# AUTENTICACIÓN Y AUTORIZACIÓN
# ============================================
gem "devise", "~> 4.9" # Autenticación de usuarios
gem "devise-jwt", "~> 0.12" # JWT para APIs con Devise
gem "pundit", "~> 2.4" # Autorización basada en políticas

# ============================================
# MULTITENANCY Y JERARQUÍAS
# ============================================
gem "acts_as_tenant", "~> 1.0" # Multitenancy con aislamiento por tenant_id
gem "ancestry", "~> 4.3" # Árboles jerárquicos (nodos organizacionales)

# ============================================
# MULTI-IDIOMA
# ============================================

gem "rails-i18n"
gem "i18n-tasks", group: :development
gem "route_translator"
gem "mobility", "~> 1.3.2"

# ============================================
# AUDITORÍA Y SOFT DELETES
# ============================================
gem "paper_trail", "~> 16.0" # Versionado y auditoría de cambios
gem "discard", "~> 1.3" # Soft deletes (borrado lógico)

# ============================================
# API CON GRAPE
# ============================================
gem "grape", "~> 3.0" # Framework para construir APIs REST
gem "grape-entity", "~> 1.0" # Serialización de respuestas
gem "grape-swagger", "~> 2.1" # Documentación Swagger automática
gem "grape-swagger-rails", "~> 0.7" # UI de Swagger para visualizar la documentación

# ============================================
# CORS (Cross-Origin Resource Sharing)
# ============================================
gem "rack-cors" # Permitir peticiones desde frontend en otro dominio

# ============================================
# VALIDACIONES Y UTILIDADES
# ============================================
gem "email_validator", "~> 2.2" # Validación avanzada de emails
gem "aasm", "~> 5.5.1" # Manejo de maquina de estados

gem "kaminari"
gem "sprockets-rails"
# gem "solid_queue", "~> 1.2.4"
# gem "solid_cache", "~> 1.0.10"


group :development, :test do
  # Debugging
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Linting y formateo
  gem "rubocop-rails-omakase", require: false

  # Variables de entorno
  gem "dotenv-rails", "~> 3.1"
end

group :development do
  # Consola mejorada
  gem "pry-rails"

  # Detectar queries N+1
  # gem "bullet", "~> 7.2"

  # Anotaciones de esquema en modelos
  # gem "annotate", "~> 3.2"
end
