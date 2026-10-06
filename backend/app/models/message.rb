class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :user, class_name: 'User', inverse_of: :messages

  field :to,                 type: String
  field :body,               type: String
  field :twilio_sid,         type: String
  field :status,             type: String, default: 'queued'
  field :error_message,      type: String

  validates :to, presence: true, format: { with: /\A\+?[1-9]\d{1,14}\z/, message: 'must be a valid phone number (E.164 format)' }
  validates :body, presence: true, length: { maximum: 1600 }
  validates :user_id, presence: true

  index({ user_id: 1, created_at: -1 })
  index({ twilio_sid: 1 }, { unique: true, sparse: true })
end
