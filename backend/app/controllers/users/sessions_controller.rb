module Users
  class SessionsController < Devise::SessionsController
    skip_before_action :authenticate_user!
    skip_before_action :verify_signed_out_user, only: :destroy

    def create
      request_body = request.body.string
      body = JSON.parse(request_body)
      user_params = body['user'] || {}

      email = user_params['email'].to_s.strip
      password = user_params['password'].to_s

      response.headers['Content-Type'] = 'application/json'

      if email.blank? || password.blank?
        response.status = 422
        self.response_body = JSON.generate({ errors: { base: 'Please provide email and password' } })
        return
      end

      user = User.find_by(email: email)

      if user.nil?
        response.status = 401
        self.response_body = JSON.generate({ errors: { base: 'No account found with this email. Please sign up.' } })
      elsif user.valid_password?(password)
        token = generate_jwt(user)
        response.headers['Authorization'] = "Bearer #{token}"
        response.status = 200
        self.response_body = JSON.generate({ user: { id: user.id.to_s, email: user.email } })
      else
        response.status = 401
        self.response_body = JSON.generate({ errors: { base: 'Incorrect password' } })
      end
    rescue JSON::ParserError
      response.headers['Content-Type'] = 'application/json'
      response.status = 400
      self.response_body = JSON.generate({ errors: { base: 'Invalid JSON' } })
    rescue StandardError => e
      Rails.logger.error("Login error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      response.headers['Content-Type'] = 'application/json'
      response.status = 401
      self.response_body = JSON.generate({ errors: { base: 'Login failed. Please try again.' } })
    end

    def destroy
      head :no_content
    end

    private

    def generate_jwt(user)
      payload = {
        sub: user.id.to_s,
        iat: Time.current.to_i,
        exp: (Time.current + 24.hours).to_i
      }
      secret = ENV.fetch('DEVISE_JWT_SECRET_KEY')
      JWT.encode(payload, secret, 'HS256')
    end
  end
end
