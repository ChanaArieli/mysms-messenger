# Multi-stage build for production
# Stage 1: Build Angular frontend
FROM node:20-alpine as frontend-builder

WORKDIR /app/frontend

COPY frontend/package*.json ./
RUN npm install

COPY frontend/ .
RUN npm run build -- --configuration production

# Stage 2: Build Rails backend
FROM ruby:3.3.12-slim as backend-builder

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
  build-essential \
  git \
  && rm -rf /var/lib/apt/lists/*

COPY backend/Gemfile ./
COPY backend/Gemfile.lock ./

RUN bundle install --jobs=4 --without development test

COPY backend/ .

# Stage 3: Final production image
FROM ruby:3.3.12-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
  curl \
  && rm -rf /var/lib/apt/lists/*

# Copy gems from builder
COPY --from=backend-builder /usr/local/bundle /usr/local/bundle

# Copy built Angular app
COPY --from=frontend-builder /app/frontend/dist/frontend public

# Copy Rails app
COPY backend/ .

# Set production environment
ENV RAILS_ENV=production
ENV NODE_ENV=production

# Expose port
EXPOSE 3000

# Pre-compile assets
RUN bundle exec rake assets:precompile || true

# Start Rails server
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000"]
