class MessagesController < ApplicationController
  before_action :authenticate_user!

  def index
    messages = current_user.messages.order(created_at: :desc)
    render json: messages.map { |m| message_json(m) }
  end

  def create
    message = current_user.messages.new(message_params)
    if message.save
      send_via_twilio(message)
      render json: message_json(message), status: :created
    else
      render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:message).permit(:to, :body)
  end

  def send_via_twilio(message)
    TwilioSenderService.new(message).call
  end

  def message_json(m)
    {
      id: m.id.to_s,
      to: m.to,
      body: m.body,
      status: m.status,
      error_message: m.error_message,
      created_at: m.created_at&.iso8601
    }
  end
end
