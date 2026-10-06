class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include Devise::Controllers::Helpers

  def authenticate_user!
    token = extract_token_from_request

    if token.blank?
      response.headers['Content-Type'] = 'application/json'
      response.status = 401
      self.response_body = JSON.generate({ error: 'Missing authentication token' })
      return
    end

    begin
      payload = decode_jwt(token)
      user = User.find(payload['sub'])
      sign_in user, store: false
    rescue JWT::DecodeError, Mongoid::Errors::DocumentNotFound
      response.headers['Content-Type'] = 'application/json'
      response.status = 401
      self.response_body = JSON.generate({ error: 'Invalid or expired token' })
    end
  end

  private

  def extract_token_from_request
    auth_header = request.headers['Authorization']
    auth_header&.sub(/^Bearer /, '')
  end

  def decode_jwt(token)
    JWT.decode(token, ENV.fetch('DEVISE_JWT_SECRET_KEY'), true, { algorithm: 'HS256' }).first
  end
end
