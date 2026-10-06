module Users
  class RegistrationsController < Devise::RegistrationsController
    skip_before_action :authenticate_user!

    def create
      request_body = request.body.string
      body = JSON.parse(request_body)
      user_params = body['user'] || {}

      @user = User.new(
        email: user_params['email'],
        password: user_params['password'],
        password_confirmation: user_params['password_confirmation']
      )

      response.headers['Content-Type'] = 'application/json'
      if @user.save
        token = generate_jwt(@user)
        response.headers['Authorization'] = "Bearer #{token}"
        response.status = 201
        self.response_body = JSON.generate({ user: { id: @user.id.to_s, email: @user.email } })
      else
        response.status = 422
        self.response_body = JSON.generate({ errors: @user.errors.messages.transform_values { |msgs| msgs.join(', ') } })
      end
    rescue JSON::ParserError
      response.headers['Content-Type'] = 'application/json'
      response.status = 400
      self.response_body = JSON.generate({ errors: { base: 'Invalid JSON' } })
    rescue StandardError => e
      response.headers['Content-Type'] = 'application/json'
      response.status = 422
      self.response_body = JSON.generate({ errors: { base: "Signup failed: #{e.message}" } })
    end

    private

    def generate_jwt(user)
      payload = { sub: user.id.to_s, iat: Time.current.to_i, exp: (Time.current + 24.hours).to_i }
      secret = ENV.fetch('DEVISE_JWT_SECRET_KEY')
      JWT.encode(payload, secret, 'HS256')
    end
  end
end
