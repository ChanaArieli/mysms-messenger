class MessagesController < ApplicationController
  before_action :authenticate_user!

  def index
    messages = current_user.messages.order(created_at: :desc)
    response.headers['Content-Type'] = 'application/json'
    response.status = 200
    self.response_body = JSON.generate(messages.map { |m| message_json(m) })
  end

  def create
    body = JSON.parse(request.body.string)
    message_params = body['message'] || {}

    message = current_user.messages.new(to: message_params['to'], body: message_params['body'])
    if message.save
      send_via_twilio(message)
      response.headers['Content-Type'] = 'application/json'
      response.status = 201
      self.response_body = JSON.generate(message_json(message))
    else
      response.headers['Content-Type'] = 'application/json'
      response.status = 422
      self.response_body = JSON.generate({ errors: message.errors.full_messages })
    end
  rescue JSON::ParserError
    response.headers['Content-Type'] = 'application/json'
    response.status = 400
    self.response_body = JSON.generate({ errors: { base: 'Invalid JSON' } })
  end

  private

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
