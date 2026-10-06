module Webhooks
  class TwilioController < ActionController::API
    before_action :validate_twilio_signature!

    def status
      message = Message.find_by(twilio_sid: params['MessageSid'])

      if message
        if message.update(status: params['MessageStatus'])
          Rails.logger.info("Message #{message.id} status updated to #{params['MessageStatus']}")
        else
          Rails.logger.error("Failed to update message #{message.id}: #{message.errors.full_messages.join(', ')}")
        end
      else
        Rails.logger.warn("Webhook received for unknown message SID: #{params['MessageSid']}")
      end

      head :no_content
    end

    private

    def validate_twilio_signature!
      validator = Twilio::Security::RequestValidator.new(ENV.fetch('TWILIO_AUTH_TOKEN'))
      url = request.original_url
      params_hash = request.request_parameters
      signature = request.headers['X-Twilio-Signature']
      head :forbidden unless validator.validate(url, params_hash, signature)
    end
  end
end
