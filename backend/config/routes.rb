Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users,
    path: '',
    path_names: { sign_in: 'login', sign_out: 'logout', registration: 'signup' },
    controllers: {
      sessions: 'users/sessions',
      registrations: 'users/registrations'
    }

  resources :messages, only: [:index, :create]
  post 'webhooks/twilio/status', to: 'webhooks/twilio#status'
end
