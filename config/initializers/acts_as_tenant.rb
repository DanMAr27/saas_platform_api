# config/initializers/acts_as_tenant.rb
ActsAsTenant.configure do |config|
  # Habilitar el modo de tenant requerido por defecto
  config.require_tenant = true

  # Permitir bypass para ciertos casos (platform admins)
  config.pkey = :id
end
