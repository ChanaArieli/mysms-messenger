# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread pool size of most Ruby database
# drivers.
#
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Specifies the `worker_processes` number (usually equals to the number of `cpu_cores`).
# This is not needed on Heroku, Render, or other PaaS platforms.
# For free tier/single dyno, use 0 workers (single process mode)
workers ENV.fetch("WEB_CONCURRENCY") { 0 }

# Use the `preload_app!` method when specifying a `workers` number.
# This directive tells Puma to first boot the application and load code
# before forking the application. This takes advantage of Copy On Write
# process behavior so workers use less memory.
# Skip for single process mode to avoid initialization hangs
#
if ENV.fetch("WEB_CONCURRENCY") { 0 }.to_i > 0
  preload_app!
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# Bind to the port configured by the platform, or default to 3000
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }

# Log requests with timestamps
log_requests true
