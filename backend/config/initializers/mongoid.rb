# Configure Mongoid connection timeouts to prevent startup hangs
# This is especially important on Render where connection might take time

Mongoid.configure do |config|
  # Set connection timeout to 5 seconds to fail fast instead of hanging
  if ENV['RAILS_ENV'] == 'production'
    config.connect_timeout = 5
    config.socket_timeout = 5
  end
end
