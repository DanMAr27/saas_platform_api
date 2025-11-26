# config/initializers/devise.rb
Devise.setup do |config|
  config.mailer_sender = "noreply@example.com"

  # JWT configuration
  config.jwt do |jwt|
    jwt.secret = ENV["JWT_SECRET_KEY"]
    jwt.dispatch_requests = [
      [ "POST", %r{^/api/v1/auth/login$} ]
    ]
    jwt.revocation_requests = [
      [ "DELETE", %r{^/api/v1/auth/logout$} ]
    ]
    jwt.expiration_time = (ENV.fetch("JWT_EXPIRATION_HOURS", 24).to_i).hours.to_i
  end

  # Otras configuraciones de Devise
  require "devise/orm/active_record"
  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage = [ :http_auth, :params_auth ]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = false
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete

  # Navegación
  config.navigational_formats = []
end
