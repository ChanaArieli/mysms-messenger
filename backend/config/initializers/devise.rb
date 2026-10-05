# Devise configuration with Mongoid ORM
require 'devise/orm/mongoid'

Devise.setup do |config|
  config.mailer_sender = 'noreply@mysms.local'
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = 12

  config.jwt do |jwt|
    jwt.secret = ENV.fetch('DEVISE_JWT_SECRET_KEY')
    jwt.dispatch_requests = [['POST', %r{^/login$}], ['POST', %r{^/signup$}]]
    jwt.revocation_requests = [['DELETE', %r{^/logout$}]]
    jwt.expiration_time = 24.hours.to_i
  end
end
