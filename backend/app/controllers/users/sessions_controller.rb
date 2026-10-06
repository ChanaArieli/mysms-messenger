module Users
  class SessionsController < Devise::SessionsController
    skip_before_action :verify_signed_out_user, only: :destroy

    def create
      request_body = request.body.string
      body = JSON.parse(request_body)
      user_params = body['user'] || {}

      email = user_params['email'].to_s.strip
      password = user_params['password'].to_s

      if email.present? && password.present?
        user = User.find_by(email: email)
      end

      if user&.valid_password?(password)
        token = generate_jwt(user)
        response.headers['Content-Type'] = 'application/json'
        response.headers['Authorization'] = "Bearer #{token}"
        response.status = 200
        self.response_body = JSON.generate({ user: { id: user.id.to_s, email: user.email } })
      else
        response.headers['Content-Type'] = 'application/json'
        response.status = 401
        self.response_body = JSON.generate({ errors: { base: 'Invalid email or password' } })
      end
    rescue JSON::ParserError
      response.headers['Content-Type'] = 'application/json'
      response.status = 400
      self.response_body = JSON.generate({ errors: { base: 'Invalid JSON' } })
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
