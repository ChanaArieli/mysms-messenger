# Log boot sequence to help debug startup issues
Rails.logger.info "=" * 50
Rails.logger.info "MySMS Messenger - Production Boot"
Rails.logger.info "=" * 50
Rails.logger.info "RAILS_ENV: #{ENV['RAILS_ENV']}"
Rails.logger.info "Time: #{Time.current}"

at_exit do
  Rails.logger.info "=" * 50
  Rails.logger.info "App shutting down"
  Rails.logger.info "=" * 50
end
