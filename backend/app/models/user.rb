class User
  include Mongoid::Document
  include Mongoid::Timestamps

  devise :database_authenticatable, :registerable,
         :recoverable, :validatable

  field :email,              type: String, default: ''
  field :encrypted_password, type: String, default: ''
  field :reset_password_token,    type: String
  field :reset_password_sent_at,  type: Time
  field :remember_created_at,     type: Time

  index({ email: 1 }, { unique: true })
  index({ jti: 1 })

  validates :email, presence: true, uniqueness: true

  has_many :messages, class_name: 'Message', inverse_of: :user, dependent: :destroy
end
