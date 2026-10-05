module Webhooks
  class TwilioController < ActionController::API
    before_action :validate_twilio_signature!

    def status
      message = Message.find_by(twilio_sid: params['MessageSid'])
      message&.update(status: params['MessageStatus'])
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
