class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include Devise::Controllers::Helpers

  def authenticate_user!
    token = extract_token_from_request

    if token.blank?
      render json: { error: 'Missing authentication token' }, status: :unauthorized
      return
    end

    begin
      payload = decode_jwt(token)
      user = User.find(payload['sub'])
      sign_in user, store: false
    rescue JWT::DecodeError, Mongoid::Errors::DocumentNotFound
      render json: { error: 'Invalid or expired token' }, status: :unauthorized
    end
  end

  private

  def extract_token_from_request
    auth_header = request.headers['Authorization']
    auth_header&.sub(/^Bearer /, '')
  end

  def decode_jwt(token)
    JWT.decode(token, ENV.fetch('DEVISE_JWT_SECRET_KEY'), true, algorithm: 'HS256').first
  end
end
