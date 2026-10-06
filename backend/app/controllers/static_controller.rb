class StaticController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index]
  skip_before_action :verify_authenticity_token, only: [:index]

  def index
    render file: Rails.public_path.join('index.html'), layout: false
  end
end
