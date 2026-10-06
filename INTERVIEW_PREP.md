# Interview Preparation Guide - MySMS Messenger

## Quick Overview
A full-stack SMS messaging app built with:
- **Backend**: Rails 7.2 API (JWT auth, Twilio integration)
- **Frontend**: Angular 19 (standalone components, signals)
- **Database**: MongoDB with Mongoid ODM
- **DevOps**: Docker Compose for local development

**What it does**: Users signup/login → compose SMS → send via Twilio → view message history with delivery status

---

## Key Architecture Highlights

### Authentication Flow
```
1. User signs up/logs in
2. Devise validates credentials
3. JWT token generated (24-hour expiration)
4. Token returned in Authorization header
5. Token stored in browser localStorage
6. Auth interceptor attaches token to all requests
7. Route guard protects messenger page
```

### Message Journey
```
Frontend (Angular)           Backend (Rails)              Twilio
    ↓                              ↓                        ↓
  Compose        →    Save to DB    →    Send API    →   Queue/Send
  Validate phone          (queued)        Request         (status callback)
                                           ↓
                          Update status    ← Webhook
                         (sent/delivered)
```

### Data Relationships
```
User (has_many messages)
 ├── Email (unique, indexed)
 └── Encrypted password (Devise)

Message (belongs_to user)
 ├── to (phone number, E.164 format)
 ├── body (max 1600 chars)
 ├── status (queued/sent/delivered/failed)
 ├── twilio_sid (for webhook lookups)
 └── error_message (if status failed)
```

---

## Interview Topics You Should Know

### 1. **Why Mongoid over ActiveRecord?**
- Document-based storage fits messaging use case better
- Flexible schema - easy to add fields without migrations
- Better scaling for collections with millions of messages
- Not tied to relational constraints

### 2. **Why Angular Signals over RxJS Observables?**
- Fine-grained reactivity for simple state (loading, errors)
- Better performance - only affected components re-render
- Less boilerplate than observable chains
- Still use observables for HTTP calls (RxJS)

### 3. **JWT Token Security Decisions**
- **Tokens expire in 24 hours** (prevents indefinite access if stolen)
- **Stored in localStorage** (XSS vulnerable, but simpler than httpOnly)
- **No refresh tokens** (simpler for this scope, but less ideal for production)
- **HS256 signing** (symmetric key sufficient for internal API)

### 4. **Phone Number Validation (E.164)**
- **Format**: `+[1-9]{1-15 digits}`
- **Why**: Twilio requires E.164 format
- **Validation**: Done both client-side (UX) and server-side (security)
- **Example**: `+15551234567` (US number)

### 5. **Error Handling Approach**
- **Synchronous errors**: Try-catch blocks
- **HTTP errors**: Observable error callbacks
- **401 errors**: Global interceptor handling (redirect to login)
- **Validation errors**: Return from backend with specific messages

---

## Bugs Found & Fixed

### Critical Issues (3)
1. **Double-Rendering**: Controllers had conflicting `respond_with` methods
   - **Impact**: Potential 500 errors on signup/login
   - **Fix**: Removed duplicate handlers

2. **Request Body Consumed Twice**: Each parse consumed the stream
   - **Impact**: Second reader gets empty string
   - **Fix**: Cache in variable before parsing

3. **No 401 Handling**: Frontend components didn't handle expired tokens
   - **Impact**: Users stuck on page with error
   - **Fix**: Added global interceptor error catch

### High-Severity Issues (2)
4. **Timing Attack**: Email validation took different time if user existed
   - **Impact**: Attackers could enumerate valid emails
   - **Fix**: Normalize both paths by checking presence first

5. **No Phone Validation**: Could send to "abc" or invalid numbers
   - **Impact**: Failed messages with confusing errors
   - **Fix**: E.164 regex validation (backend + frontend)

### Medium Issues (4)
6. **Webhook Logging Missing**: Silent failures if message not found
7. **Race Condition on Refresh**: Auth guard could reject valid token
8. **ViewChild Unsafe**: Missing children would crash component
9. **Unhandled Exceptions**: Sync throws not caught

**Solution**: Added error boundaries, logging, null checks, and try-catch blocks

---

## What You Should Be Ready to Discuss

### Design Decisions
- Why API-only Rails instead of full Rails?
- Why standalone Angular components vs. NgModules?
- Why MongoDB for this use case?
- How would you add real-time message delivery (WebSockets)?

### Scaling Considerations
- How to handle 1M users?
  - DB sharding by user_id
  - Message queue for Twilio (background job)
  - Redis caching for session tokens
- How to reduce costs with Twilio?
  - Batch API calls
  - Regional number pooling
  - Usage monitoring/alerts

### Security Improvements
- Add rate limiting (to prevent SMS spam)
- Implement refresh tokens (for better UX)
- Add audit logging (who sent what when)
- Encrypt phone numbers in DB
- Add 2FA for sensitive accounts

### Testing Strategy
- Unit tests for validation logic
- Integration tests for auth flow
- E2E tests for message send
- Mocking Twilio API in tests

---

## Code Quality Notes

### What's Good
✅ Clean separation of concerns (models, controllers, services)
✅ Proper error handling with meaningful messages
✅ Validation at both client and server
✅ Type-safe TypeScript on frontend
✅ Environment variable configuration

### What Could Be Better
⚠️ No automated tests (would add before production)
⚠️ No rate limiting (vulnerable to abuse)
⚠️ No comprehensive logging/monitoring
⚠️ Phone numbers stored as plain text
⚠️ No pagination on message list

---

## Interview Red Flags to Avoid

### Don't Say
- ❌ "I just used what felt easy"
- ❌ "Security isn't important for this"
- ❌ "I didn't think about scaling"
- ❌ "Tests slow down development"

### Do Say
- ✅ "I chose this because [tradeoff analysis]"
- ✅ "Here's how I'd improve security..."
- ✅ "For 1M users, I would..."
- ✅ "Tests provide [ROI benefit]..."

---

## Quick Facts to Remember

| Aspect | Detail |
|--------|--------|
| **JWT Expiration** | 24 hours |
| **Phone Format** | E.164 (e.g., +15551234567) |
| **Message Length** | Max 1600 characters |
| **Auth Method** | JWT in Authorization header |
| **Database** | MongoDB via Mongoid |
| **Session Management** | Stateless (no refresh tokens yet) |
| **Twilio Trial** | Verified numbers only |
| **CORS** | Configured for localhost:4200 |

---

## Running the App During Interview

```bash
# Start everything
docker-compose up

# Access
Frontend: http://localhost:4200
Backend API: http://localhost:3000

# Test endpoint
curl -X POST http://localhost:3000/signup \
  -H "Content-Type: application/json" \
  -d '{"user": {"email": "test@example.com", "password": "password123", "password_confirmation": "password123"}}'
```

---

## Final Notes

**This app demonstrates:**
- Full-stack development (Rails + Angular)
- API design (RESTful endpoints)
- Database modeling (MongoDB relationships)
- Authentication (JWT implementation)
- Error handling (graceful failures)
- External integrations (Twilio API)
- Security awareness (validation, XSS protection)
- Problem-solving (12 bugs found and fixed)

**Be ready to explain:**
- Why you chose each technology
- How the system handles failure cases
- What you'd do differently with more time
- How you'd scale for 10x users
