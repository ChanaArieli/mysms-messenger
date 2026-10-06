class MessagesController < ApplicationController
  def index
    limit = (params[:limit] || 50).to_i.clamp(1, 100)
    start_time = Time.current
    messages = current_user.messages.order(created_at: :desc).limit(limit)
    query_time = Time.current - start_time

    serialize_start = Time.current
    response.headers['Content-Type'] = 'application/json'
    response.status = 200
    self.response_body = JSON.generate(messages.map { |m| message_json(m) })
    serialize_time = Time.current - serialize_start

    Rails.logger.info("Messages#index - Query: #{query_time*1000.0}ms, Serialize: #{serialize_time*1000.0}ms, Total: #{(query_time + serialize_time)*1000.0}ms, Count: #{messages.count}")
  end

  def create
    start_time = Time.current
    body = JSON.parse(request.body.string)
    message_params = body['message'] || {}

    message = current_user.messages.new(to: message_params['to'], body: message_params['body'])
    if message.save
      save_time = Time.current - start_time
      send_via_twilio(message)
      twilio_time = Time.current - start_time - save_time

      response.headers['Content-Type'] = 'application/json'
      response.status = 201
      self.response_body = JSON.generate(message_json(message))

      Rails.logger.info("Messages#create - Save: #{save_time*1000.0}ms, Twilio: #{twilio_time*1000.0}ms, Total: #{(Time.current - start_time)*1000.0}ms")
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
