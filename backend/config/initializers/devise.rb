# Devise configuration with Mongoid ORM
require 'devise/orm/mongoid'

Devise.setup do |config|
  config.mailer_sender = 'noreply@mysms.local'
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = true
  config.stretches = 12
  config.navigational_formats = []

  config.jwt do |jwt|
    jwt.secret = ENV['DEVISE_JWT_SECRET_KEY'] || Rails.application.secrets.secret_key_base
    jwt.dispatch_requests = [['POST', %r{^/login$}], ['POST', %r{^/signup$}]]
    jwt.revocation_requests = []
    jwt.expiration_time = 24.hours.to_i
  end
end
