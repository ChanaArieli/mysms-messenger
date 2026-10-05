module Users
  class RegistrationsController < Devise::RegistrationsController
    def create
      body = JSON.parse(request.body.string)
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
    end

    private

    def generate_jwt(user)
      payload = { sub: user.id.to_s, iat: Time.current.to_i }
      secret = ENV.fetch('DEVISE_JWT_SECRET_KEY')
      JWT.encode(payload, secret, 'HS256')
    end

    def respond_with(resource, _opts = {})
      if resource.persisted?
        render json: {
          user: { id: resource.id.to_s, email: resource.email }
        }, status: 201
      else
        render json: {
          errors: resource.errors.messages.transform_values { |msgs| msgs.join(', ') }
        }, status: 422
      end
    end
  end
end
