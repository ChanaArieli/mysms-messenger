# MySMS Messenger

A full-stack SMS messaging application built with Rails (backend), Angular (frontend), MongoDB, and Twilio for sending SMS.

## Features

- **User Authentication**: Username/password signup and login with JWT tokens
- **Send SMS**: Send messages via Twilio API to verified phone numbers
- **Message History**: View all messages sent with status tracking (queued, sent, delivered, failed)
- **Delivery Status**: Real-time status updates via Twilio webhooks
- **Cross-origin API**: Rails API backend and Angular frontend on separate domains

## Architecture

- **Backend**: Ruby on Rails 7.2 API
- **Frontend**: Angular 19 standalone components
- **Database**: MongoDB (via Mongoid ORM)
- **SMS Provider**: Twilio
- **Authentication**: Devise + devise-jwt (JWT token-based)
- **Containerization**: Docker & Docker Compose for local development

## Prerequisites

- Docker & Docker Compose
- Twilio account (free trial) with verified phone number
- MongoDB Atlas URI (or local MongoDB)

## Local Setup

1. **Clone the repository** and navigate to the project:
   ```bash
   cd mysms-messenger
   ```

2. **Create a `.env` file** from `.env.example` with your Twilio credentials:
   ```bash
   cp .env.example .env
   ```
   
   Edit `.env` and add:
   - `TWILIO_ACCOUNT_SID`: Your Twilio Account SID
   - `TWILIO_AUTH_TOKEN`: Your Twilio Auth Token
   - `TWILIO_FROM_NUMBER`: Your Twilio phone number (e.g., +1234567890)

3. **Start the development servers**:
   ```bash
   docker-compose up
   ```
   
   This will start:
   - **Backend API**: http://localhost:3000
   - **Frontend**: http://localhost:4200
   - **MongoDB**: mongodb://localhost:27017

4. **Access the app** at http://localhost:4200

## Usage

1. **Sign Up**: Create a new account with email and password
2. **Login**: Sign in with your credentials
3. **Send Message**: Enter a phone number and compose your message
   - **Note**: On Twilio free trial, you can only send to verified numbers (see your Twilio dashboard under "Develop > Messaging > Try it Out > Send an SMS")
   - Messages will be prefixed with "Sent from a Twilio trial account"
4. **View History**: See all sent messages with delivery status
5. **Status Updates**: Message status updates when Twilio confirms delivery (or failure)

## Environment Variables

Create a `.env` file with:

```
# Twilio credentials
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_FROM_NUMBER=+1234567890

# Twilio webhook callback URL (set during deploy)
TWILIO_STATUS_CALLBACK_URL=

# Frontend origin (for CORS)
FRONTEND_ORIGIN=http://localhost:4200

# JWT secret key
DEVISE_JWT_SECRET_KEY=dev-key-change-in-production

# MongoDB URI (optional, defaults to local)
MONGODB_URI=mongodb://mongodb:27017/mysms_dev
```

## API Endpoints

### Authentication
- `POST /signup` - Create new user
- `POST /login` - User login, returns JWT token
- `DELETE /logout` - User logout, revokes token

### Messages
- `GET /messages` - List user's messages
- `POST /messages` - Send new message

### Webhooks
- `POST /webhooks/twilio/status` - Twilio delivery status callback

## Deployment

See [DEPLOY.md](DEPLOY.md) for Render.com deployment instructions.

## Known Limitations

- **Twilio Trial**: Can only send to verified phone numbers (you can add your own)
- **Trial Message Prefix**: Messages include "Sent from a Twilio trial account"
- **Status Updates**: Local development doesn't receive Twilio webhooks (set `TWILIO_STATUS_CALLBACK_URL` during deploy)

## Development Notes

- **Backend**: Rails API-only mode with Mongoid (no ActiveRecord)
- **Frontend**: Angular standalone components with functional route guards
- **Auth**: Devise with JWT tokens stored in browser localStorage
- **CORS**: Configured to allow cross-origin requests from frontend to backend

## Testing

```bash
# Run Rails tests
docker-compose exec backend bundle exec rspec

# Run Angular tests
docker-compose exec frontend npm run test
```

## License

Private project for assessment purposes.
