FROM ruby:3.3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
  build-essential \
  git \
  && rm -rf /var/lib/apt/lists/*

# Copy Gemfile
COPY Gemfile ./
COPY Gemfile.lock ./

# Install gems
RUN bundle install --jobs=4

# Copy application code
COPY . .

# Expose port
EXPOSE 3000

# Start Rails server
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000"]
