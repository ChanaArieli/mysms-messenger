class TwilioSenderService
  def initialize(message)
    @message = message
  end

  def call
    return unless twilio_ready?

    client = Twilio::REST::Client.new(ENV.fetch('TWILIO_ACCOUNT_SID'), ENV.fetch('TWILIO_AUTH_TOKEN'))
    twilio_msg = client.messages.create(
      from: ENV.fetch('TWILIO_FROM_NUMBER'),
      to: @message.to,
      body: @message.body,
      status_callback: ENV.fetch('TWILIO_STATUS_CALLBACK_URL', '')
    )
    @message.update(twilio_sid: twilio_msg.sid, status: 'sent')
  rescue Twilio::REST::RestError => e
    @message.update(status: 'failed', error_message: e.message)
    Rails.logger.error("Twilio error: #{e.message}")
  end

  private

  def twilio_ready?
    %w[TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER].all? do |var|
      ENV[var].present?
    end
  end
end
