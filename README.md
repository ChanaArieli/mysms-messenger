# MySMS Messenger

A full-stack SMS messaging application built with Rails (backend), Angular (frontend), MongoDB, and Twilio for sending SMS.

## Features

- **User Authentication**: Username/password signup and login with JWT tokens
- **Send SMS**: Send messages via Twilio API to verified phone numbers
- **Message History**: View all messages sent with status tracking (queued, sent, delivered, failed)
- **Delivery Status**: Real-time status updates via Twilio webhooks
- **Cross-origin API**: Rails API backend and Angular frontend on separate domains

## Architecture

📖 **[Read the Architecture & Scaling Strategy Document](./ARCHITECTURE.md)** - Comprehensive design decisions, future scaling considerations, and architectural trade-offs for 10k+ users

### Tech Stack
- **Backend**: Ruby on Rails 7.2 API-only mode
- **Frontend**: Angular 19 with standalone components
- **Database**: MongoDB (via Mongoid ODM)
- **SMS Provider**: Twilio
- **Authentication**: Devise + devise-jwt (JWT tokens)
- **Containerization**: Docker & Docker Compose

### System Design

#### High-Level Flow
```
Client Browser (Angular)
        ↓
   [Auth Service] ← → [Auth Endpoints] (Rails)
        ↓                   ↓
   [Messenger UI]      [User Model]
        ↓                (MongoDB)
   [Message Service]  ← → [Messages Controller] 
        ↓                   ↓
   [Compose/List]     [Message Model]
                            ↓
                  [TwilioSenderService]
                            ↓
                      Twilio API
```

#### Data Models

**User**
- Email (unique, indexed)
- Encrypted password (via Devise)
- Timestamps (created_at, updated_at)
- Relationships: has_many messages

**Message**
- `to`: Recipient phone number
- `body`: Message content (max 1600 chars)
- `status`: One of [queued, sent, delivered, failed]
- `twilio_sid`: Unique Twilio message identifier
- `error_message`: Error details if status is failed
- `user_id`: Foreign key to User
- `created_at`: Message creation timestamp
- Indexes: (user_id, created_at) for efficient queries; twilio_sid for webhook lookups

#### Authentication Flow

1. **Signup/Login**
   - User submits email & password to `/signup` or `/login`
   - Rails validates credentials and generates JWT token
   - Token returned in Authorization header
   - Token stored in browser localStorage
   - Auth interceptor attaches token to all subsequent requests

2. **Route Protection**
   - `authGuard` on MessengerComponent prevents unauthorized access
   - Unauthenticated users redirected to login page
   - Token validation happens client-side (presence check) and server-side (Devise)

#### Message Lifecycle

1. **Composition** (Frontend)
   - User enters phone number and message in ComposeBoxComponent
   - Form validates phone number format and message length

2. **Sending** (Backend)
   - Frontend POSTs to `/messages` with `{message: {to, body}}`
   - MessagesController creates Message record with status: 'queued'
   - TwilioSenderService immediately sends via Twilio API
   - On success: status updated to 'sent', twilio_sid stored
   - On failure: status set to 'failed', error_message recorded

3. **Status Updates**
   - In production, Twilio sends webhook callbacks to `/webhooks/twilio/status`
   - Updates message status to 'delivered' or 'failed' based on callback
   - (Note: Local development doesn't receive webhooks; status stays 'sent')

4. **Display** (Frontend)
   - MessageListComponent fetches messages via GET /messages
   - Returns user's messages ordered by created_at (newest first)
   - MessageCardComponent displays each message with status badge
   - Auto-refreshes or updates after compose success

#### API Endpoints

| Method | Endpoint | Auth | Purpose |
|--------|----------|------|---------|
| POST | `/signup` | No | Create user account |
| POST | `/login` | No | Authenticate & get JWT |
| DELETE | `/logout` | Yes | Clear auth session |
| GET | `/messages` | Yes | List user's messages |
| POST | `/messages` | Yes | Send new message |
| POST | `/webhooks/twilio/status` | No | Receive delivery status updates |

#### Frontend Component Architecture

```
AppComponent (routes)
├── LoginComponent (email/password form)
└── MessengerComponent (protected)
    ├── ComposeBoxComponent (form input)
    │   └── AuthService, MessageService
    ├── MessageListComponent (display)
    │   ├── MessageCardComponent (individual message)
    │   └── MessageService
    └── Logout button
```

#### Cross-Origin Communication

- Frontend runs on `localhost:4200`
- Backend runs on `localhost:3000`
- CORS configured via `config/initializers/cors.rb`
- Credentials (Authorization header) included in all requests
- Responses always include Content-Type: application/json

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

The app is deployed and live at: **[https://mysms-messenger-4bpy.onrender.com/](https://mysms-messenger-4bpy.onrender.com/)**

To deploy your own instance, ensure you have Twilio credentials and follow the standard deployment process for Rails + Angular apps on Render.com or similar platforms.

## Known Limitations

- **Twilio Trial**: Can only send to verified phone numbers (you can add your own)
- **Trial Message Prefix**: Messages include "Sent from a Twilio trial account"
- **Status Updates**: Local development doesn't receive Twilio webhooks (set `TWILIO_STATUS_CALLBACK_URL` during deploy)

## Design Decisions

### Backend Choices
- **Rails API-only** over full Rails: Cleaner separation of concerns, smaller footprint since we're not rendering HTML
- **Mongoid ODM** over ActiveRecord: Document-based storage better matches the flexible nature of messages and user data; easier scaling for a messaging system
- **Service Object Pattern** (TwilioSenderService): Isolates external service logic from controller, making it testable and reusable
- **JWT Authentication** over sessions: Stateless auth for API-only applications; tokens can be used across domains

### Frontend Choices
- **Angular Standalone Components**: Modern approach without NgModules; cleaner, more intuitive component structure
- **Angular Signals**: Fine-grained reactivity; better performance than observables for simple state (UI loading, error messages)
- **Functional Route Guards**: Composable auth checks at route level; prevents unauthorized access before component initialization
- **Auth Interceptor**: Centralized token injection into all requests; single source of truth for authentication header

### Infrastructure
- **Docker Compose**: Local development mirrors production environment; easy onboarding
- **MongoDB Atlas URI support**: Flexible database configuration for dev/staging/prod
- **Twilio Free Trial**: Full SMS functionality without paid integration during development

## Development Notes

- **Backend**: Rails API-only mode with Mongoid (no ActiveRecord)
- **Frontend**: Angular standalone components with functional route guards
- **Auth**: Devise with JWT tokens stored in browser localStorage
- **CORS**: Configured to allow cross-origin requests from frontend to backend
- **Webhook Handling**: Local dev doesn't receive Twilio webhooks (no public IP); production requires `TWILIO_STATUS_CALLBACK_URL`

## Testing

```bash
# Run Rails tests
docker-compose exec backend bundle exec rspec

# Run Angular tests
docker-compose exec frontend npm run test
```

## License

Private project for assessment purposes.
