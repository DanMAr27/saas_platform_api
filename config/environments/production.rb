require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Active Storage (archivo local, ajustar si usas S3 u otro servicio)
  config.active_storage.service = :local

  # SSL settings
  config.assume_ssl = true
  config.force_ssl = true

  # Logging
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  # Deprecations
  config.active_support.report_deprecations = false

  # Cache store
  config.cache_store = :memory_store

  # Active Job: usar inline para producción simple en Render
  # o puedes cambiar por :async si prefieres background threads
  config.active_job.queue_adapter = :inline

  # Mailer defaults
  config.action_mailer.default_url_options = { host: "example.com" }

  # I18n fallbacks
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only show :id in inspections
  config.active_record.attributes_for_inspect = [ :id ]

  # Host authorization (opcional, ajustar según tu dominio)
  # config.hosts = ["example.com"]
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
