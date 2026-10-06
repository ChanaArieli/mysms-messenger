# Puma single-threaded configuration for Render free tier
# Minimize threads and workers to avoid initialization hangs

threads 2, 5
workers 0

port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }

# Don't preload app in production to avoid timeout on startup
# Render will send SIGTERM if app takes too long to start
# Plugin for graceful restarts
plugin :tmp_restart
