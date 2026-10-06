class UsersController < ApplicationController
  def me
    response.headers['Content-Type'] = 'application/json'
    response.status = 200
    self.response_body = JSON.generate({ user: { id: current_user.id.to_s, email: current_user.email } })
  end
end
