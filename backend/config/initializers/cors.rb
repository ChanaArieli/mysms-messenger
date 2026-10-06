Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow multiple origins for development and production
    origins ENV.fetch('FRONTEND_ORIGIN', 'http://localhost:4200'),
            'localhost',
            'localhost:4200',
            /\A.*\.onrender\.com\z/  # Allow all Render.com domains

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      expose: ['Authorization', 'Content-Type', 'X-Total-Count'],
      credentials: false
  end
end
