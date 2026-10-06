# Minimal Puma configuration for Render
threads 2, 5
workers 0
port ENV.fetch("PORT", 3000)
plugin :tmp_restart
