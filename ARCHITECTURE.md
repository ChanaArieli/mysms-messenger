# Architecture & Scaling Strategy
## MySMS Messenger App

**Document Date**: October 6, 2026  
**Purpose**: Design decisions, future scaling considerations, and architectural trade-offs  
**Audience**: Technical interviewers, architects, future maintainers

---

## 1. Database Scaling & Sharding Strategy

### Current State & Rationale:

**Current State:**
MongoDB + Mongoid is a good fit for the current stage because:
- Document model matches message structure naturally (flexible schema for status, error_message, metadata)
- Easy to scale horizontally via sharding
- Development velocity is high

**At Scale (millions of users, thousands of msg/sec):**

I'd **keep MongoDB but evolve the architecture**:

1. **Horizontal Sharding Strategy**
   - Shard key: `user_id` (not global message volume, but per-user history)
   - Rationale: Most queries are user-centric (GET /messages returns MY messages)
   - Distributes write load evenly across shards
   - Avoids hot shards (unlike sharding by `created_at`)

2. **Time-Series Collection** (MongoDB 5.0+)
   - Convert messages to time-series collection for automatic bucketing
   - Reduces storage by 50-80% for historical messages
   - Perfect for write-heavy, read-heavy access patterns
   - TTL indexes automatically clean up old messages

3. **Archive Strategy**
   - Messages older than 90 days → cheaper MongoDB tier or S3 + Athena
   - Rationale: Users rarely query old messages; compliance allows it
   - Saves ~40% of storage costs

4. **Alternative Considered & Rejected:**
   - **PostgreSQL + JSONB**: Could work, but sharding is harder (Citus adds complexity). PostgreSQL isn't designed for horizontal scale like MongoDB.
   - **Cassandra**: Overkill for this use case; better for distributed analytics/metrics
   - **DynamoDB**: Lock-in to AWS; less flexible query language; higher per-request costs at scale

**Why MongoDB Over SQL at Scale:**
- Native sharding (not bolted on like Citus)
- No JOIN overhead (messages are self-contained documents)
- Easy to add fields without migrations (error_metadata, delivery_millis, etc.)
- Cost-effective for high-volume writes

---

## 2. Indexing & Query Optimization



**Indexing Strategy:**

```javascript
// Existing compound index (good):
db.messages.createIndex({ user_id: 1, created_at: -1 })

// Additional indexes needed at scale:

// 1. Webhook lookups (status updates from Twilio)
db.messages.createIndex({ twilio_sid: 1 }, { unique: true })
// Rationale: Every webhook hits this. Single field, unique constraint.

// 2. Querying failed messages (retry jobs)
db.messages.createIndex({ status: 1, created_at: 1 })
// Rationale: Background job scans "failed" messages older than 1 hour for retries

// 3. Monitoring/analytics (optional, separate collection?)
db.messages.createIndex({ created_at: 1, status: 1 })
// Rationale: "How many delivered in the last hour?" queries

// 4. Phone number searches (compliance/blocking)
db.messages.createIndex({ to: 1, user_id: 1 })
// Rationale: If abuse reports come in, quickly find all messages to a number
```

**Index Pruning:**
- Remove any unused indexes (check MongoDB Profiler)
- Each index adds ~20% write overhead (maintain during INSERT/UPDATE)

**Sharding:**

| Shard Key | Pros | Cons | Verdict |
|-----------|------|------|---------|
| `user_id` | Even distribution; all user queries hit 1 shard | Can't easily query across users (OK, compliance prefer it) | ✅ **USE THIS** |
| `created_at` (time-based) | Chronological queries fast | Hot shard on current time; old shards cold | ❌ Avoid |
| `to` (phone number) | Compliance queries fast | Highly skewed if one number popular | ❌ Avoid |
| Compound `(user_id, created_at)` | Both queries optimized | Increases shard key space | Possible, but overkill |

**Recommended**: Shard on `user_id`. Keeps data isolated, simplifies compliance, speeds up 95% of queries.

---

## 3. Message Queue & Async Processing



**Current Problem:**
```
POST /messages
  ↓
Create Message record (status: queued)
  ↓
Call Twilio API (BLOCKING) ← Twilio is slow → User waits 2-5 seconds
  ↓
Update status + return
```

Issues:
- If Twilio times out (>30s), request fails, but message was created (orphaned)
- User sees failed response even though Twilio accepted it
- API becomes slow under Twilio latency spikes
- No retry mechanism for transient failures

**Evolution by Scale:**

**Stage 1: Current (< 100 msg/sec)**
- Keep synchronous for simplicity
- Add timeout: `Twilio.send_message(timeout: 5.seconds)`
- If timeout: set status to "queued", rely on webhook to update later
- Trade-off: Simple; acceptable UX if webhooks work

**Stage 2: Introduce Job Queue (> 100 msg/sec)**
- Use **Sidekiq** (Redis-backed background jobs)
- Flow:
  ```
  POST /messages
    ↓
  Create Message (status: queued) + enqueue SidekiqJob
    ↓
  Return immediately to user ← Now instant
    ↓
  [Async] SidekiqJob sends via Twilio
    ↓
  Update message status (sent/failed)
  ```

- Benefits:
  - API returns immediately (no Twilio latency)
  - Automatic retries (Sidekiq configurable: 25x retry with exponential backoff)
  - Failed messages visible in Sidekiq UI
  - Decouples Twilio availability from API availability

- Configuration:
  ```ruby
  class SendMessageJob
    include Sidekiq::Job
    sidekiq_options retry: 25, dead: true
    
    def perform(message_id)
      message = Message.find(message_id)
      TwilioSenderService.send(message)
    rescue TwilioError => e
      message.update(error_message: e.message)
      raise e  # Sidekiq retries
    end
  end
  ```

**Stage 3: Distributed Message Queue (> 10k msg/sec)**
- Scale beyond single Redis instance
- Use **Kafka** or **RabbitMQ**:
  - Multiple producers (frontend servers) → single durable queue
  - Multiple consumers (workers) pulling jobs in parallel
  - Kafka advantages: immutable log, easy to replay if bugs
  - RabbitMQ advantages: simpler setup, built-in acks

- Kafka flow:
  ```
  Producers (3x API servers)
       ↓
    [Kafka Topic: messages-to-send]
       ↓
    Consumers (10x Worker pods)
       ↓
    Twilio API
  ```

**Delivery Guarantees:**

| Guarantee | Mechanism | Cost | Use Case |
|-----------|-----------|------|----------|
| **At-most-once** | Fire and forget | Fastest | Analytics, non-critical |
| **At-least-once** | Job stays in queue until ack | Requires dedup | Messaging (we need this) |
| **Exactly-once** | At-least-once + dedup | Slowest, complex | Financial, critical |

**For SMS:**
- Use **At-least-once** + **idempotency key**
- When Twilio confirms send, check if `twilio_sid` already set
- If yes: Twilio retransmitted (network glitch), skip
- If no: This is first send, update status
- Prevents duplicate messages

---

## 4. Real-Time Status Updates & Webhooks



**Current Approach:**
- Twilio → `POST /webhooks/twilio/status`
- Direct database update in request handler
- At scale: 1000s of webhooks/sec → database saturation

**Issues:**
- Each webhook = 1 database write
- No deduplication (Twilio retries webhooks if no 200 response)
- No ordering guarantee (webhooks may arrive out-of-order)
- If database is slow, webhooks back up and timeout

**Evolution:**

**Stage 1: Webhook Buffer (current scale)**
- Add idempotency: check if message already has status
- Return 200 immediately after parsing
- Then update database asynchronously:
  ```ruby
  POST /webhooks/twilio/status
    ↓
  Parse webhook payload
  Return 200 to Twilio (acknowledge receipt)
    ↓
  [Async] Enqueue UpdateStatusJob
    ↓
  Job: Find message by twilio_sid, update status
  ```
- Benefit: Twilio doesn't retry; decouples webhook receipt from DB write

**Stage 2: Webhook Queue (1000+ webhook/sec)**
- Pre-allocate: Why hit the database twice?
- Use **in-memory cache** (Redis) as webhook buffer:
  ```ruby
  POST /webhooks/twilio/status
    ↓
  Redis.lpush("webhook_queue", webhook_payload)
  Return 200
    ↓
  [Async] Consumer job: read from Redis in batches
    ↓
  Batch update messages (bulk write to MongoDB)
  ```
- Benefits:
  - Webhooks always fast (Redis writes are nanoseconds)
  - Batch writes reduce database load (1 write per 100 webhooks vs. 100 writes)
  - Handles Twilio retries naturally (same message_id overwrites old entry)

**Stage 3: Event Streaming (10k+ webhook/sec)**
- Kafka topic: `sms-status-updates`
- Webhooks → Kafka (fast, durable)
- Multiple consumers can subscribe:
  - Consumer 1: Update MongoDB
  - Consumer 2: Update real-time cache (Redis) for WebSocket push
  - Consumer 3: Send to analytics/metrics system
- Benefits:
  - Decoupled; webhook system independent of database
  - Replay capability (replay last 7 days if bug found)
  - Natural fan-out (many systems can listen)

**Deduplication Strategy:**
```javascript
// Webhook arrives: { message_id: "123", status: "delivered", timestamp: 1696000000 }

// Check Redis cache:
const cached = Redis.get("webhook:delivered:123")
if (cached && cached.timestamp >= webhook.timestamp) {
  // Already processed this or a newer status
  return 200
}

// New or newer status: process it
Redis.set("webhook:delivered:123", webhook, EX: 86400) // 24h TTL
Database.update(message: 123, status: "delivered")
```

---

## 5. Monitoring & Failure Recovery



**Current State:**
- Failed messages stored in `error_message` field
- No automatic retry mechanism
- User must manually resend

**Problems:**
- Silent failures (what if a message fails after sending to Twilio but webhook never arrives?)
- No visibility into failure causes (rate limits, invalid number, Twilio outage?)
- Compliance issue: no audit trail

**SLA Design:**

```
Tier: Standard SMS
- 99.5% of messages delivered within 60 seconds
- Failed messages: automatic retry for 24 hours
- Dead-letter handling: user notified if undeliverable after 24h
- Monitoring: alerting if delivery rate < 98%
```

**Failure Tracking System:**

```javascript
Message Schema:
{
  _id: ObjectId,
  user_id: ObjectId,
  to: "+1234567890",
  body: "Hello",
  
  // Status tracking
  status: "delivered",  // queued | sent | delivered | failed
  
  // Attempt tracking (NEW)
  attempts: [
    {
      attempt_number: 1,
      twilio_sid: "SM12345abc",
      sent_at: ISODate("2026-10-06T10:00:00Z"),
      status: "sent"
    },
    {
      attempt_number: 2,
      twilio_sid: "SM12345def",
      sent_at: ISODate("2026-10-06T10:05:00Z"),
      status: "delivered",
      delivered_at: ISODate("2026-10-06T10:05:10Z")
    }
  ],
  
  // Latest attempt summary
  current_twilio_sid: "SM12345def",
  delivered_at: ISODate("2026-10-06T10:05:10Z"),
  
  // Failure details
  failure_reason: null,
  error_message: null,
  
  // Compliance
  created_at: ISODate("2026-10-06T10:00:00Z"),
  updated_at: ISODate("2026-10-06T10:05:10Z")
}
```

**Retry Logic:**

```ruby
class RetryFailedMessagesJob
  def perform
    # Find messages that:
    # 1. Failed
    # 2. Last attempt < 1 hour ago
    # 3. Fewer than 5 attempts
    # 4. Created within last 24 hours
    
    failed = Message.where(
      status: 'failed',
      created_at: { '$gte' => 24.hours.ago },
      'attempts.0' => { '$exists' => true }
    ).where('attempts' => { '$size' => { '$lt' => 5 } })
     .where('attempts.-1.sent_at' => { '$lt' => 1.hour.ago })
    
    failed.each do |message|
      # Idempotency: use message._id as dedup key
      # Twilio accepts duplicate SID if same request ID
      
      attempt = {
        attempt_number: message.attempts.length + 1,
        sent_at: Time.now,
        status: 'pending'
      }
      
      begin
        result = TwilioSenderService.send(
          message,
          idempotency_key: "#{message._id}-attempt-#{attempt[:attempt_number]}"
        )
        attempt.update(twilio_sid: result.sid, status: 'sent')
      rescue => e
        attempt.update(status: 'error', error: e.message)
      end
      
      message.update(
        attempts: message.attempts + [attempt],
        current_twilio_sid: attempt[:twilio_sid]
      )
    end
  end
end

# Run every 15 minutes
class RetryFailedMessagesJob
  include Sidekiq::Job
  sidekiq_options retry: 3
  
  def perform
    # ... retry logic
  end
end

# Cron:
sidekiq_cron_configuration = {
  'retry-failed-messages' => {
    'class' => 'RetryFailedMessagesJob',
    'cron' => '*/15 * * * *'
  }
}
```

**Webhook Deduplication:**

```ruby
POST /webhooks/twilio/status
  message_id = find_message_by_twilio_sid(webhook.message_sid)
  
  # Idempotency check
  recent_status = message.attempts.last
  if recent_status.twilio_sid == webhook.message_sid &&
     recent_status.status == webhook.status &&
     (Time.now - recent_status.updated_at) < 5.minutes
    # Duplicate webhook (Twilio retry); ignore
    return 200
  end
  
  # Real status update
  message.attempts.last.update(status: webhook.status)
  message.update(status: webhook.status)
  return 200
```

**Monitoring & Alerting:**

```ruby
# Cloudwatch/Datadog metrics
- delivery_rate: (delivered + failed) / sent
  - Alert if < 95% for 10 minutes
- failure_rate: failed / attempted
  - Alert if > 2%
- retry_attempts: distribution histogram
  - Alert if p99 > 4 attempts (indicates systemic issue)
- webhook_latency: time from send to webhook receipt
  - Alert if p99 > 60 seconds
- dead_letters: messages failed after 24h
  - Daily report to ops

# Dashboard:
- Real-time delivery rate by hour
- Top failure reasons (invalid number, rate limit, etc.)
- Twilio service status integration
- Failed message queue depth
```

**Dead-Letter Handling:**

```ruby
class DeadLetterMessagesJob
  def perform
    # Find messages with status=failed, created > 24h ago, no webhook received
    dead_letters = Message.where(
      status: 'failed',
      created_at: { '$lt' => 24.hours.ago },
      delivered_at: { '$exists' => false }
    )
    
    dead_letters.each do |msg|
      # Option 1: Mark as dead-letter, notify user
      msg.update(status: 'dead_letter', notified_at: Time.now)
      
      # Option 2: Send notification to user
      DeliveryFailureMailer.deliver_later(msg.user, msg)
      
      # Option 3: Log for manual investigation
      DeadLetterLog.create(message_id: msg._id, reason: msg.error_message)
    end
  end
end
```

---

## 6. Security & Authentication at Scale



**Current Approach & Risks:**

```javascript
// Current: JWT in localStorage
localStorage.setItem('auth_token', jwt)

// Every request:
const token = localStorage.getItem('auth_token')
Authorization: Bearer <token>
```

**Security Risks:**

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **XSS Attack** (malicious script reads localStorage) | **CRITICAL** | See below |
| **Token Theft** (attacker reads localStorage) | High | Short expiry + refresh tokens |
| **CSRF** (cross-site request forgery) | Medium | No risk with JWT (stateless) |
| **Token Revocation** (can't revoke at scale) | High | Token blacklist in Redis |
| **Token Size** (grows with claims) | Low | Keep claims minimal |

**XSS Prevention:**

```javascript
// ❌ DON'T do this (current approach):
localStorage.setItem('auth_token', jwt)
// XSS attack: <script>fetch('/steal?token=' + localStorage.token)</script>

// ✅ DO THIS:
// Store token in httpOnly, Secure cookie (backend sets it)
// Frontend cannot access it (immune to XSS)

POST /login
Backend validates credentials
Backend sets: Set-Cookie: auth_token=<jwt>; HttpOnly; Secure; SameSite=Strict
Response: 200 OK (no token in JSON body)

// Frontend makes requests:
GET /messages
Browser automatically attaches cookie
Backend validates JWT from cookie
```

**Token Lifecycle:**

```ruby
# Tokens: short-lived access + long-lived refresh

# 1. Login
POST /login { email, password }
  ↓
Backend validates
Issues 2 tokens:
  - access_token: 15-minute JWT (claims: user_id, exp=now+15m)
  - refresh_token: 7-day JWT (claims: user_id, version=1, exp=now+7d)

Set-Cookie: access_token=<jwt>; HttpOnly; Secure; SameSite=Strict
Set-Cookie: refresh_token=<jwt>; HttpOnly; Secure; SameSite=Strict; Path=/refresh

Response: 200 OK { user: { id, email } }

# 2. Access token expires (15m later)
GET /messages
Browser sends access_token cookie
Backend: token expired
Returns 401 Unauthorized

# 3. Frontend detects 401, calls refresh
POST /refresh
Browser sends refresh_token cookie
Backend validates refresh_token:
  - Signature valid?
  - Exp not reached?
  - Version matches stored version? (for revocation)
  
Issues new access_token (same 15-min expiry)
Set-Cookie: access_token=<new_jwt>; ...
Response: 200 OK

# 4. User logs out
DELETE /logout
Backend increments refresh_token version in database
Old refresh_token becomes invalid (version mismatch)
Clear cookies
Response: 200 OK
```

**Token Revocation at Scale:**

```ruby
# User model
User.schema do
  field :refresh_token_version, type: Integer, default: 0
  field :revoked_at, type: DateTime
end

# During logout
def logout
  current_user.update(refresh_token_version: current_user.refresh_token_version + 1)
  # All existing refresh tokens now invalid (version mismatch)
  # User must re-login
  response.delete_cookie(:refresh_token)
  response.delete_cookie(:access_token)
end

# During token refresh
def refresh
  token = decode_jwt(request.cookies[:refresh_token])
  user = User.find(token.user_id)
  
  if user.refresh_token_version != token.version
    # User revoked tokens (logged out from another device)
    return 401 Unauthorized
  end
  
  # Issue new access token
  new_token = JWT.encode({
    user_id: user.id,
    exp: Time.now + 15.minutes,
    iat: Time.now
  }, Rails.application.secrets.jwt_secret)
  
  set_auth_cookie(:access_token, new_token)
  render json: { user: user }
end
```

**Token Blacklist (Optional, for Additional Security):**

```ruby
# If you need to revoke access tokens immediately (not just at expiry)
# Example: user reports account compromise

Redis cache:
blacklist:token:{jti} = true, EX: 900s (expires with token)

# Issue tokens with unique JTI (JWT ID)
token = JWT.encode({
  user_id: user.id,
  jti: SecureRandom.uuid,
  exp: Time.now + 15.minutes
}, secret)

# Validate token
def validate_jwt(token)
  payload = JWT.decode(token, secret)
  
  # Check blacklist
  if Redis.exists("blacklist:#{payload['jti']}")
    raise InvalidToken
  end
  
  payload
end

# Revoke immediately (emergency)
def emergency_revoke(user_id)
  user.active_sessions.each do |session|
    Redis.set("blacklist:#{session.jti}", true, EX: 900)
  end
  user.update(refresh_token_version: user.refresh_token_version + 1)
end
```

**At Scale (millions of users):**

| Scenario | Solution |
|----------|----------|
| Refresh token validation latency | Cache `(user_id, version)` in Redis; expires with token |
| Blacklist memory (billions of revoked tokens) | Don't use global blacklist; use per-token expiry instead |
| Logout not immediate | Accept 15-min delay (token lifetime) OR use token version + Redis cache |
| Single sign-out (logout all devices) | Increment refresh_token_version; all active tokens become invalid |

**Recommended: Token Version + Expiry (no blacklist needed)**
- Simpler at scale
- Acceptable 15-min delay
- Logout next refresh (< 15 min)
- Emergency: revoke via version bump

---

## 7. Rate Limiting & Abuse Prevention



**Rate Limiting Strategy:**

**Layer 1: IP-Based (Global)**
```ruby
# Framework: rack-attack (middleware)
# Prevents: DDoS, brute-force

Rack::Attack.throttle('requests by IP', limit: 300, period: 1.minute) do |req|
  req.ip
end

# Response: 429 Too Many Requests
# Rejected at Nginx/load balancer level (before hitting Rails)
```

**Layer 2: User-Based (Per Authenticated User)**
```ruby
# Prevents: One user spamming others

Rack::Attack.throttle('messages by user', limit: 100, period: 1.hour) do |req|
  req.user_id if req.authenticated? && req.post?('/messages')
end

# Example: user can send max 100 messages/hour
# Violate: return 429, message not created

# Alternative: queued but rate-limited
if user_message_count_today >= LIMIT:
  message.update(status: 'queued_rate_limited')
  return 200 (message accepted, but delayed)
```

**Layer 3: Recipient-Based (Prevent Spam to Same Number)**
```ruby
# Prevents: Spam to single victim

rate_limit = {
  limit: 10,
  period: 1.hour,
  key: "messages:to:#{phone_number}:#{user_id}"
}

def create_message
  to = params[:message][:to]
  user = current_user
  
  count = Redis.incr("messages:to:#{to}:#{user.id}")
  if count == 1
    Redis.expire("messages:to:#{to}:#{user.id}", 3600)
  end
  
  if count > 10
    return 429, { error: "Too many messages to #{to} in last hour" }
  end
  
  # Create message...
end
```

**Layer 4: Twilio-Level (Rate Limiting by Destination)**
```ruby
# Prevents: Hitting Twilio API limits

# Strategy: Queue messages, consume from queue at controlled rate
# Use Sidekiq with limited concurrency:

Sidekiq::Client.push({
  'class' => 'SendMessageJob',
  'args' => [message_id],
  'queue' => 'sms_send'
})

# Sidekiq configuration:
sidekiq.yml:
---
:max_dead_letter_queue: 100
:queues:
  - [default, 20]       # 20 concurrent workers
  - [sms_send, 5]       # Only 5 concurrent Twilio sends
  - [webhooks, 10]

# Result: Max 5 concurrent Twilio API calls
# More messages queue and wait (user perceives as "delayed" but not failed)
```

**Layer 5: Plan-Based (Tiered Limits)**
```ruby
User schema:
  plan: 'free' | 'pro' | 'enterprise'

Message limits:
  free: 100 messages/month
  pro: 10,000 messages/month
  enterprise: unlimited

class Message < ApplicationRecord
  validate :user_plan_limit
  
  def user_plan_limit
    case user.plan
    when 'free'
      limit = 100
      period = 1.month
    when 'pro'
      limit = 10000
      period = 1.month
    when 'enterprise'
      return  # No limit
    end
    
    count = user.messages.created_after(period.ago).count
    if count >= limit
      errors.add(:base, "Monthly message limit reached")
    end
  end
end
```

**DDoS Protection (Webhook Endpoint):**

```ruby
# Problem: Attacker floods /webhooks/twilio/status with fake requests
# POST /webhooks/twilio/status { message_sid: "fake", status: "delivered" }

# Solution: Webhook signature validation (Twilio provides this!)

POST /webhooks/twilio/status
  twilio_signature = request.headers['X-Twilio-Signature']
  auth_token = ENV['TWILIO_AUTH_TOKEN']
  
  # Twilio signs every webhook with HMAC-SHA1
  # Attacker cannot forge signature without auth token
  
  computed_sig = Digest::SHA1.hexdigest(
    "https://myapp.com/webhooks/twilio/status" + # full URL
    request.body.read +                          # request body
    auth_token
  )
  
  unless computed_sig == twilio_signature
    return 403 Forbidden  # Reject unsigned webhooks
  end
  
  # Safe to process webhook
end

# Additional: Rate limit webhook endpoint separately
Rack::Attack.throttle('twilio webhooks', limit: 10000, period: 1.minute) do |req|
  'twilio_webhook' if req.post?('/webhooks/twilio/status')
end
```

**Monitoring Rate Limiting:**

```ruby
# Metrics to track
- rate_limit_violations_per_minute (by layer)
- user_monthly_quota_exhaustion (by plan)
- false_positives (legitimate traffic rejected)
- DDoS attempts blocked

# Alert if:
- Single IP more than 1000 requests/min (likely DDoS)
- Same phone receiving >20 messages/hour from different users (spam victim)
- 10% of traffic hitting rate limits (misconfigured limits)
```

**Summary:**
- **Layer 1 (IP)**: Nginx/Cloudflare, prevents DDoS
- **Layer 2 (User)**: Per-user limits, prevents bulk spam
- **Layer 3 (Recipient)**: Prevents targeting one user
- **Layer 4 (Provider)**: Sidekiq queue throttling
- **Layer 5 (Plans)**: Business logic for tiers
- **Webhook**: HMAC signature validation + IP-based rate limit

---

## 8. Pagination for Message History



**Current Problem:**
```
GET /messages
Backend: Message.where(user_id: current_user.id).order(created_at: :desc)
         → Loads ALL messages into memory
         → Returns entire array to frontend
         → Slow on first load (1000+ messages)
         → Memory intensive (MongoDB + Rails)
```

Issues:
- Loading 10,000 messages into memory is wasteful
- Network payload huge (transfer all messages to frontend)
- Frontend struggles to render 10k DOM elements
- User waits 5+ seconds for initial load
- Database query slow (full scan without limits)

**Solution: Cursor-Based Pagination**

Why cursor-based over offset-based?

| Strategy | How It Works | Pros | Cons | Use Case |
|----------|-------------|------|------|----------|
| **Offset** | `LIMIT 20 OFFSET 40` | Simple, stateless | Slow with large offsets (skip 10k rows) | Small datasets |
| **Cursor** | `WHERE created_at < 1696000000 LIMIT 20` | Fast (index scan), no skip | Slightly complex | Large datasets, messaging |

**Recommended: Cursor-Based**

**Backend Implementation:**

```ruby
# Message model
class Message
  field :to, type: String
  field :body, type: String
  field :status, type: String
  field :created_at, type: DateTime
  field :twilio_sid, type: String
  field :user_id, type: ObjectId
  
  # Index for pagination query
  index({ user_id: 1, created_at: -1 })
end

# Messages controller
class MessagesController < ApplicationController
  before_action :authenticate_user!
  
  def index
    # Parameters:
    # page_size: 20 (how many messages per page)
    # cursor: "2026-10-06T10:00:00Z" (timestamp of last message)
    # direction: "next" or "prev"
    
    page_size = [params[:page_size].to_i, 1].max
    page_size = [page_size, 100].min  # Cap at 100
    cursor = params[:cursor]&.to_datetime
    direction = params[:direction] || 'next'
    
    query = Message.where(user_id: current_user.id)
    
    # Query logic: load page_size + 1 to detect if more pages exist
    if cursor
      if direction == 'next'
        # Load messages BEFORE cursor
        query = query.where(created_at: { '$lt' => cursor })
      else
        # Load messages AFTER cursor (for previous page)
        query = query.where(created_at: { '$gt' => cursor })
      end
    end
    
    # Always order by newest first
    messages = query.order(created_at: :desc)
                    .limit(page_size + 1)
                    .to_a
    
    # Detect if more pages exist
    has_more = messages.length > page_size
    messages = messages.take(page_size) if has_more
    
    # Build next/prev cursors
    next_cursor = messages.last&.created_at.iso8601 if has_more
    prev_cursor = messages.first&.created_at.iso8601 if cursor
    
    render json: {
      messages: MessageSerializer.new(messages),
      pagination: {
        has_more: has_more,
        next_cursor: next_cursor,
        prev_cursor: prev_cursor,
        page_size: page_size
      }
    }
  end
  
  def create
    message_params = params.require(:message).permit(:to, :body)
    
    message = current_user.messages.build(message_params)
    message.status = 'queued'
    
    if message.save
      # Immediately send async (enqueue job)
      SendMessageJob.perform_later(message.id)
      
      render json: MessageSerializer.new(message), status: :created
    else
      render json: { errors: message.errors }, status: :unprocessable_entity
    end
  end
end
```

**Frontend Implementation (Angular):**

```typescript
// message.service.ts
@Injectable({ providedIn: 'root' })
export class MessageService {
  private readonly api = inject(HttpClient)
  private readonly baseUrl = 'http://localhost:3000'
  
  // Cursor-based pagination state
  private readonly messages = signal<Message[]>([])
  private readonly pagination = signal<PaginationState>({
    nextCursor: null,
    prevCursor: null,
    hasMore: false,
    pageSize: 20
  })
  
  readonly messages$ = this.messages.asReadonly()
  readonly pagination$ = this.pagination.asReadonly()
  
  // Load first page
  loadMessages(pageSize: number = 20): void {
    this.fetchMessages(pageSize, null, 'next')
  }
  
  // Load next page
  loadNextPage(): void {
    const state = this.pagination()
    if (!state.nextCursor) return
    
    this.fetchMessages(state.pageSize, state.nextCursor, 'next')
  }
  
  // Load previous page
  loadPreviousPage(): void {
    const state = this.pagination()
    if (!state.prevCursor) return
    
    this.fetchMessages(state.pageSize, state.prevCursor, 'prev')
  }
  
  // Core fetch logic
  private fetchMessages(
    pageSize: number,
    cursor: string | null,
    direction: 'next' | 'prev'
  ): void {
    const params = new HttpParams()
      .set('page_size', pageSize.toString())
      .set('direction', direction)
    
    if (cursor) {
      params = params.set('cursor', cursor)
    }
    
    this.api
      .get<{
        messages: Message[]
        pagination: PaginationState
      }>(`${this.baseUrl}/messages`, { params })
      .subscribe({
        next: (response) => {
          this.messages.set(response.messages)
          this.pagination.set(response.pagination)
        },
        error: (err) => console.error('Error loading messages:', err)
      })
  }
}

// Type definitions
interface Message {
  id: string
  to: string
  body: string
  status: 'queued' | 'sent' | 'delivered' | 'failed'
  created_at: string
}

interface PaginationState {
  nextCursor: string | null
  prevCursor: string | null
  hasMore: boolean
  pageSize: number
}
```

**Frontend UI Component:**

```typescript
// message-list.component.ts
@Component({
  selector: 'app-message-list',
  template: `
    <div class="message-list">
      <div *ngFor="let msg of messageService.messages$()" class="message-card">
        <p>{{ msg.body }}</p>
        <span class="status" [class]="msg.status">{{ msg.status }}</span>
        <small>{{ msg.created_at | date:'short' }}</small>
      </div>
      
      <div class="pagination-controls" *ngIf="messageService.pagination$() as pag">
        <button 
          (click)="messageService.loadPreviousPage()"
          [disabled]="!pag.prevCursor"
          class="btn-prev">
          ← Previous
        </button>
        
        <span class="page-info">
          Showing {{ messageService.messages$().length }} messages
          <span *ngIf="pag.hasMore">(more available)</span>
        </span>
        
        <button 
          (click)="messageService.loadNextPage()"
          [disabled]="!pag.nextCursor"
          class="btn-next">
          Next →
        </button>
      </div>
    </div>
  `
})
export class MessageListComponent implements OnInit {
  readonly messageService = inject(MessageService)
  
  ngOnInit(): void {
    this.messageService.loadMessages(20)
  }
}
```

**Infinite Scroll Alternative:**

```typescript
// For modern UX: auto-load next page when user scrolls to bottom

@Component({
  selector: 'app-message-list',
  template: `
    <div class="message-list" (scroll)="onScroll($event)">
      <div *ngFor="let msg of messageService.messages$()" class="message-card">
        {{ msg.body }}
      </div>
      
      <div *ngIf="isLoading()" class="spinner">Loading...</div>
    </div>
  `
})
export class MessageListComponent {
  protected readonly messageService = inject(MessageService)
  readonly isLoading = signal(false)
  
  onScroll(event: Event): void {
    const element = event.target as HTMLElement
    const threshold = element.scrollHeight - element.scrollTop - 500
    
    // User scrolled to within 500px of bottom
    if (threshold < element.clientHeight && !this.isLoading()) {
      const pag = this.messageService.pagination()
      if (pag.hasMore) {
        this.isLoading.set(true)
        
        this.messageService.loadNextPage()
        // When loadNextPage completes, set isLoading to false
        setTimeout(() => this.isLoading.set(false), 500)
      }
    }
  }
}
```

**API Query Performance:**

```ruby
# Query explanation: How MongoDB executes this efficiently
# Index: { user_id: 1, created_at: -1 }

# Query: Find messages before cursor
db.messages.find({
  user_id: user_id_oid,
  created_at: { $lt: ISODate("2026-10-06T10:00:00Z") }
})
.sort({ created_at: -1 })
.limit(21)

# Execution plan:
# 1. Use index on (user_id, created_at)
# 2. Seek to user_id (fast index lookup)
# 3. Scan 21 documents where created_at < cursor (fast, ordered index)
# 4. Return 20 documents (+ 1 to detect more)

# Performance: O(1) + O(20) = O(1) regardless of total message count!
```

**Common Pitfalls:**

❌ **Don't do offset-based:**
```ruby
# SLOW on large offsets
Message.where(user_id: id)
       .order(created_at: :desc)
       .offset(1000)
       .limit(20)
# MongoDB must skip 1000 documents even though we discard them!
```

❌ **Don't fetch all messages into memory:**
```ruby
# BAD: Loads all 50k messages
messages = Message.where(user_id: id).to_a
messages.sort_by(&:created_at).reverse
messages.slice(0, 20)
```

✅ **Do use cursor + index:**
```ruby
# FAST: Uses index, fetches only 21 docs
Message.where(user_id: id, created_at: {'$lt' => cursor})
       .order(created_at: :desc)
       .limit(21)
```

---

## 9. Caching Strategy for Message Reading



**When to Cache (and when NOT to):**

| Scenario | Cache? | Why |
|----------|--------|-----|
| User reads own messages | ❌ No | Messages change frequently (status updates, new messages) |
| Admin views user messages | ✅ Maybe | Reads only, doesn't change often |
| Message stats/analytics | ✅ Yes | Expensive aggregation query, changes slowly |
| Status badges (queued/sent) | ❓ Complex | High cache invalidation cost |
| Auth token validation | ✅ Yes | Expensive JWT verification, token lifetime controls TTL |

**Key Insight: Caching Messages is Expensive**

Reason: Message status changes constantly (queued → sent → delivered)
- Cache hit rate will be low (most reads happen before status changes)
- Cache invalidation becomes complex (need to invalidate on every webhook)
- Network latency to Redis (1-5ms) vs. MongoDB (5-20ms)—not huge gain

**Better Strategy: Query Optimization + Connection Pooling**

Instead of caching, optimize the database:

```ruby
# 1. Connection pooling (reduce connection overhead)
# mongoid.yml
development:
  clients:
    default:
      database: mysms_dev
      hosts:
        - localhost:27017
      options:
        max_pool_size: 20        # Connection pool
        min_pool_size: 5
        wait_queue_timeout: 1

# 2. Projection (only fetch fields you need)
# DON'T fetch all fields
Message.where(user_id: id)
       .order(created_at: :desc)
       .limit(20)

# DO project only needed fields
Message.where(user_id: id)
       .order(created_at: :desc)
       .limit(20)
       .only(:id, :to, :body, :status, :created_at)

# 3. Use read preference (read from secondaries if replica set)
Message.with(read: { mode: :secondary }) do
  Message.where(user_id: id).limit(20)
end
```

**When Caching IS Worth It:**

**Scenario 1: Message Stats/Analytics**

```ruby
# Query: "How many messages sent today?"
# Without cache: Full collection scan
Message.where(user_id: id, created_at: { '$gte' => 1.day.ago })
       .count  # Slow: scans all matching documents

# With cache:
def message_count_today
  cache_key = "user:#{user_id}:message_count:today"
  
  Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    Message.where(
      user_id: user_id,
      created_at: { '$gte' => Time.now.beginning_of_day }
    ).count
  end
end

# Result: First call slow, next 59 calls instant (1 hour TTL)
```

**Scenario 2: User Profile Cache (Status + Message Count)**

```ruby
class User
  def message_stats
    cache_key = "user:#{id}:stats"
    
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      {
        total_messages: messages.count,
        delivered_count: messages.where(status: 'delivered').count,
        failed_count: messages.where(status: 'failed').count,
        avg_delivery_time: calculate_avg_delivery_time
      }
    end
  end
  
  # Invalidate cache when message status changes
  def invalidate_stats_cache
    Rails.cache.delete("user:#{id}:stats")
  end
end

# In webhook handler:
def update_status
  message = Message.find_by(twilio_sid: params[:MessageSid])
  message.update(status: params[:MessageStatus])
  
  # Invalidate user's stats cache
  message.user.invalidate_stats_cache
end
```

**Scenario 3: Message Content Caching (Read-Only)**

Only cache if messages are immutable (which they're not in our case):

```ruby
# ❌ DON'T cache individual messages
message = Message.find(id)  # Don't cache this

# ✅ DO cache if you had immutable, read-only data
# Example: "Get message by ID" in a system where messages never change
Rails.cache.fetch("message:#{id}", expires_in: 1.day) do
  Message.find(id)
end
```

**Smart Caching Pattern: Cache Invalidation on Write**

```ruby
class Message
  after_save :invalidate_caches
  
  def invalidate_caches
    # When message created/updated, invalidate relevant caches
    Rails.cache.delete("user:#{user_id}:stats")
    Rails.cache.delete("user:#{user_id}:messages:page:1")
    # Don't cache other pages—they're too volatile
  end
end

# Webhook updates status
def webhooks_twilio_status
  message = Message.find_by(twilio_sid: params[:MessageSid])
  old_status = message.status
  
  message.update(status: params[:MessageStatus])
  
  # Status changed: invalidate stats cache
  if message.status != old_status
    message.user.invalidate_stats_cache
  end
end
```

**Recommended Caching Strategy (by scale):**

**Stage 1: Current (< 10k messages/user)**
- ❌ Don't cache messages (too volatile)
- ✅ Cache user stats (refreshed hourly)
- ✅ Cache auth tokens (already done via JWT)
- Tool: Rails cache (memory) or Redis

**Stage 2: Scaling (10k-100k messages/user)**
- ❌ Still don't cache full messages
- ✅ Cache aggregated stats
- ✅ Cache frequently-accessed metadata
- ✅ Add read replicas for read-heavy workloads
- Tool: Redis + MongoDB replica set

**Stage 3: Massive Scale (100k+ messages/user)**
- ❌ Still don't cache volatile messages
- ✅ Cache everything else
- ✅ Use separate cache tier (ElastiCache)
- ✅ Consider CQRS (Command Query Responsibility Segregation)
  - Separate write path (MongoDB) from read path (cache-heavy)
- Tool: Redis cluster + MongoDB sharding

**Performance Comparison:**

```
Without any optimization:
- GET /messages → MongoDB query → 150ms
- Network round trip → +50ms
- Total: 200ms

With cursor pagination (no cache):
- GET /messages (page 2) → MongoDB query (uses index) → 20ms
- Network round trip → +50ms
- Total: 70ms ✅ 3x faster!

With cache (stats only):
- GET /messages stats → Redis hit → 2ms
- Payload smaller → +10ms
- Total: 12ms ✅ 17x faster!
```

**Don't Cache If:**
1. Data changes frequently (> 10% of reads update it)
2. Consistency is critical (compliance, financial)
3. Invalidation is complex (affects many cache keys)
4. Data size is huge (each message object is large)

**Recommended Implementation (Pragmatic):**

```ruby
class MessagesController < ApplicationController
  def index
    page_size = params[:page_size] || 20
    cursor = params[:cursor]
    direction = params[:direction] || 'next'
    
    # No message caching—just optimize the query
    messages = Message.where(user_id: current_user.id)
    
    if cursor
      if direction == 'next'
        messages = messages.where(created_at: {'$lt' => cursor})
      else
        messages = messages.where(created_at: {'$gt' => cursor})
      end
    end
    
    # Optimization 1: Index on (user_id, created_at)
    # Optimization 2: Project only needed fields
    messages = messages.order(created_at: :desc)
                      .limit(page_size + 1)
                      .only(:id, :to, :body, :status, :created_at)
                      .to_a
    
    has_more = messages.length > page_size
    messages = messages.take(page_size) if has_more
    
    # Cache user stats (not messages)
    user_stats = Rails.cache.fetch(
      "user:#{current_user.id}:stats",
      expires_in: 1.hour
    ) do
      {
        total: current_user.messages.count,
        delivered: current_user.messages.where(status: 'delivered').count
      }
    end
    
    render json: {
      messages: MessageSerializer.new(messages),
      pagination: { has_more: has_more, next_cursor: messages.last&.created_at },
      stats: user_stats
    }
  end
end
```

**Summary:**
- **Don't cache messages** (too volatile, low hit rate)
- **Do cache stats** (expensive queries, slow change rate)
- **Do optimize queries** (indexing, projection, connection pooling)
- **Add cache when bottleneck proven** (measure first with APM)

---

## 10. Separate Read & Write Databases



**The Short Answer:**
Start with **read replicas** (same database, multiple copies), not separate databases. Only use completely separate databases (CQRS) when read optimization becomes a bottleneck that replicas can't solve.

**Traffic Pattern Analysis:**

For your SMS app:
```
Writing (POST /messages):
  - Create message: 1 write per message sent
  - Webhook updates: 1 write per delivery update
  - Total: 100 writes/second at scale

Reading (GET /messages):
  - Users fetch message list: ~10-50 reads per active user per day
  - Background jobs query messages: ~5 reads per minute
  - Metrics/analytics: ~1 read per minute
  - Total: 1000+ reads/second at scale

Ratio: 1000 reads : 100 writes = 10:1
```

**Yes, reads > writes. But does that mean separate databases?**

---

## Strategy 1: Read Replicas (Simplest, Start Here)

**What it is:**
- Primary database: accepts all writes
- Replica databases: synchronized copies, accepts reads only
- MongoDB handles replication automatically

```
Write request:
  Client → [Primary MongoDB] → {write to disk} → replicate to replicas

Read request:
  Client → [Replica 1, 2, 3] → {read from disk} ✅ Fast, no contention
```

**Setup:**
```ruby
# mongoid.yml
development:
  clients:
    default:
      database: mysms_dev
      hosts:
        - primary.mongodb.local:27017
      options:
        write_concern:
          w: 1  # Wait for primary write only (fast)
          
    read_replica:
      database: mysms_dev
      hosts:
        - replica1.mongodb.local:27017
        - replica2.mongodb.local:27017
        - replica3.mongodb.local:27017
      options:
        read_preference: :secondary  # Always read from replicas

# In controller:
class MessagesController < ApplicationController
  def index
    # Read from replica (fast, doesn't block writes)
    Message.with(client: :read_replica)
           .where(user_id: current_user.id)
           .order(created_at: :desc)
           .limit(20)
           .to_a
  end
  
  def create
    # Write to primary (consistency guaranteed)
    Message.with(client: :default)
           .create(message_params)
  end
end
```

**Pros:**
- ✅ Simple: still one logical database
- ✅ Automatic failover: if primary dies, replica becomes primary
- ✅ Consistent: replicas are always in sync (eventual consistency < 1ms)
- ✅ Cost-effective: replicas can be smaller/cheaper than primary

**Cons:**
- ❌ Reads still use same schema/indexes as writes
- ❌ Can't optimize read schema differently than write schema
- ❌ Replication lag (usually < 1ms, but possible)

**When it's enough:**
- < 100k requests/second
- Reads and writes have similar access patterns
- Consistency is important (< 1 second delay acceptable)

---

## Strategy 2: CQRS with Separate Databases (Advanced)

**What it is:**
- Write database: optimized for inserts, simple schema
- Read database: optimized for queries, denormalized for speed

```
Write path:
  Client POST /messages
    ↓
  [Write DB] Create message record
    ↓
  Event: MessageCreated published
    ↓
  Read DB consumer: denormalize + update read store
    ↓
  [Read DB] Store optimized version (cached, indexed for reads)

Read path:
  Client GET /messages
    ↓
  [Read DB] Query optimized read model
    ↓
  Return instantly (no joins, no aggregations)
```

**Example: Simple CQRS Implementation**

```ruby
# Write-side: Keep it simple
class Message
  field :to, type: String
  field :body, type: String
  field :status, type: String
  field :user_id, type: ObjectId
  field :created_at, type: DateTime
  
  after_save :publish_message_event
  
  def publish_message_event
    event = {
      type: 'message_created',
      message_id: self.id,
      user_id: self.user_id,
      timestamp: Time.now
    }
    Redis.publish('message_events', event.to_json)
  end
end

# Read-side: Optimized for queries
class MessageReadModel
  collection_name :messages_read_cache
  
  field :message_id, type: ObjectId        # Reference to write model
  field :user_id, type: ObjectId
  field :to, type: String
  field :body, type: String
  field :status, type: String
  field :delivered_at, type: DateTime      # Denormalized from webhook
  field :delivery_time_ms, type: Integer   # Pre-calculated for analytics
  field :user_email, type: String          # Denormalized from User
  field :created_at, type: DateTime
  
  # Indexes optimized for reads
  index({ user_id: 1, created_at: -1 })
  index({ status: 1, created_at: -1 })
  index({ user_id: 1, status: 1 })
end

# Consumer: Listen to events and update read model
class MessageReadModelSync
  include Sidekiq::Job
  
  def perform
    redis = Redis.new
    redis.subscribe('message_events') do |on|
      on.message do |channel, data|
        event = JSON.parse(data)
        
        case event['type']
        when 'message_created'
          sync_created_message(event)
        when 'message_status_updated'
          sync_status_update(event)
        end
      end
    end
  end
  
  private
  
  def sync_created_message(event)
    message = Message.find(event['message_id'])
    user = message.user
    
    # Create optimized read model
    MessageReadModel.create(
      message_id: message.id,
      user_id: message.user_id,
      to: message.to,
      body: message.body,
      status: message.status,
      user_email: user.email,    # Denormalized
      created_at: message.created_at
    )
  end
  
  def sync_status_update(event)
    read_model = MessageReadModel.find_by(
      message_id: event['message_id']
    )
    
    delivered_at = Time.parse(event['delivered_at'])
    delivery_time = (delivered_at - read_model.created_at).to_i * 1000  # ms
    
    read_model.update(
      status: event['status'],
      delivered_at: delivered_at,
      delivery_time_ms: delivery_time
    )
  end
end

# Reader: Super fast, no joins or aggregations needed
class MessagesController < ApplicationController
  def index
    # Read from read model (lightning fast)
    messages = MessageReadModel.where(user_id: current_user.id)
                               .order(created_at: :desc)
                               .limit(20)
    
    render json: MessageSerializer.new(messages)
  end
  
  def stats
    # Analytics query: still fast because delivery_time_ms is pre-calculated
    stats = MessageReadModel.where(user_id: current_user.id)
                            .where(status: 'delivered')
                            .aggregate([
                              { '$group' => {
                                  _id: nil,
                                  avg_delivery_time: { '$avg' => '$delivery_time_ms' },
                                  total: { '$sum' => 1 }
                                }}
                            ])
    
    render json: stats
  end
end
```

**Pros:**
- ✅ Read queries are extremely fast (no joins, pre-calculated fields)
- ✅ Can optimize read schema completely differently
- ✅ Write DB stays simple (single responsibility)
- ✅ Easy to scale reads independently
- ✅ Perfect for complex read patterns (analytics, reporting)

**Cons:**
- ❌ Complex: two databases to manage
- ❌ Eventual consistency: read model lags behind writes (100ms-1s)
- ❌ Syncing logic can have bugs (duplicate events, missed updates)
- ❌ Operational overhead (monitor 2 databases, 2 connections)
- ❌ Storage: read model duplicates data

**When to use:**
- > 100k requests/second
- Reads are completely different from writes
- Analytics/reporting is important
- Can tolerate eventual consistency (100ms-1s delay)

---

## Strategy 3: Separate Physical Databases (Enterprise)

**What it is:**
Completely separate database instances:
- PostgreSQL for writes (excellent transactional consistency)
- Elasticsearch/ClickHouse for reads (columnar, optimized for analytics)

```
Write path:
  POST /messages
    ↓
  PostgreSQL INSERT
    ↓
  Kafka event
    ↓
  Elasticsearch indexing
    ↓
  Read queries instant

Result: Writes go to transactional DB, reads hit search/analytics engine
```

**When to use:**
- > 1M messages/day
- Need sub-100ms analytics queries
- Have dedicated ops team
- Budget for multiple database licenses

---

## Comparison Table: Which Strategy?

| Strategy | Scale | Consistency | Complexity | Cost | Best For |
|----------|-------|-------------|-----------|------|----------|
| **Single DB** | < 1k users | Strong | Low | $$ | MVP, early stage |
| **Read Replicas** | 1k-100k users | Strong | Low-Medium | $$$ | Most apps, balanced |
| **CQRS** | 100k-1M users | Eventual (100ms-1s) | High | $$$$ | Heavy reads, analytics |
| **Separate DBs** | 1M+ users | Eventual | Very High | $$$$$+ | Enterprise scale |

---

## Recommendation for Your SMS App

**Current Stage (< 10k users):**
- Single MongoDB primary is fine
- Add read replicas when reads become bottleneck

**At 10k-100k users:**
```ruby
# Use read replicas
Message.with(client: :read_replica).where(...).limit(20)
Message.with(client: :default).create(...)  # Writes to primary
```
- Cost: ~2-3x database cost (but still < $500/month)
- Complexity: Low (Mongoid handles it)
- Benefit: 10x read speed, no schema changes

**At 100k-1M users:**
```ruby
# Introduce CQRS if you need:
# 1. Sub-100ms analytics queries
# 2. Complex reporting (delivery rates, patterns, etc.)
# 3. Reads are completely different from writes
```
- Only if read optimization is proven bottleneck
- Measure first: Is the bottleneck database queries or network?

**At 1M+ users:**
- Separate databases per region
- Columnar database (ClickHouse) for analytics
- Cache layer (Redis) for hot data

---

## The Real Bottleneck (Hint: It's Not the Database)

Before separating databases, measure where time is actually spent:

```ruby
# Add APM (Application Performance Monitoring)
# New Relic, DataDog, or similar

def index
  # Measure:
  # 1. Network latency (time to reach database)
  #    Typical: 1-5ms in same datacenter
  # 2. Query time (database processing)
  #    Typical: 5-50ms for paginated query
  # 3. Serialization (converting to JSON)
  #    Typical: 10-100ms for 100 messages
  # 4. Network return (send response)
  #    Typical: 10-50ms
  
  # Total: 26-205ms for GET /messages
  
  # If total time is 50ms, database isn't the bottleneck!
  # If total time is 500ms, investigate which part.
end
```

**Most common bottlenecks (in order):**
1. **N+1 queries** (loading 100 messages, each loads user data = 101 queries)
2. **Inefficient indexing** (query scans 1M rows to return 20)
3. **Network latency** (database in different region/datacenter)
4. **Serialization** (converting huge objects to JSON)
5. **Actual database throughput** (rare before 100k+ users)

**Fix these before adding complexity:**

```ruby
# ❌ Bad: N+1 query
messages = Message.where(user_id: id).limit(20)
messages.each { |m| puts m.user.email }  # Queries user for each message!

# ✅ Good: Eager load
messages = Message.where(user_id: id).includes(:user).limit(20)

# ❌ Bad: No index
Message.where(status: 'failed')  # Scans entire collection

# ✅ Good: Index on status
Message.index({ status: 1 })
Message.where(status: 'failed').limit(20)  # Index scan

# ❌ Bad: Fetch all fields
Message.where(user_id: id).limit(20)  # Loads message + metadata

# ✅ Good: Project only needed fields
Message.where(user_id: id)
       .only(:id, :to, :body, :status, :created_at)
       .limit(20)
```

---

## Practical Evolution Path

```
Stage 0: Single MongoDB
  Cost: $100/month
  Performance: Fine for < 5k users
  
  ↓ (Metrics show 200ms GET /messages response times)
  
Stage 1: Add Read Replicas + APM
  Cost: +$200/month
  Performance: Reads now 50ms, total response 100ms
  Action: Add APM to measure actual bottleneck
  
  ↓ (APM shows reads are now bottleneck at 100k users)
  
Stage 2: Introduce CQRS (if needed)
  Cost: +$500/month (separate read database)
  Performance: Reads now 10ms, analytics instant
  Action: Build event consumer to sync read model
  
  ↓ (Operating at 1M users, global distribution needed)
  
Stage 3: Separate Databases per Region
  Cost: +$1000/month
  Performance: Geo-local reads < 5ms
```

---

## Final Answer

**Do you need separate write/read databases right now?**

No. Use this progression:
1. **Now**: Single MongoDB (you're here)
2. **At 10k users**: Add read replicas (same DB, multiple copies)
3. **At 100k users**: Consider CQRS only if metrics prove read bottleneck
4. **At 1M users**: Evaluate dedicated read databases

**Don't separate until you measure and prove it's the bottleneck.**

---

## 11. WebSocket vs Polling for Real-Time Updates


**Current Approach (Polling):**
```
Frontend: setInterval(() => GET /messages, 2000ms)  // Poll every 2 seconds
  ↓
Backend: Query MongoDB for user's messages
  ↓
Return JSON to frontend
  ↓
Frontend re-renders if changed
```

**Issues:**
- Wasteful: 30 polls/minute even if no messages sent
- Latency: User sees status 0-2 seconds after event
- Database load: N users × M polls/minute queries
- Network overhead: Redundant HTTP headers + TLS handshake

**WebSocket Approach:**
```
Frontend: ws = new WebSocket('wss://api.myapp.com/ws')
  ↓
Backend: Keep connection open, push updates instantly
  ↓
(Twilio webhook arrives)
  ↓
Backend sends: { type: 'message_status', message_id: "123", status: "delivered" }
  ↓
Frontend receives, updates UI instantly
```

**Trade-Offs:**

| Metric | Polling | WebSocket |
|--------|---------|-----------|
| **Latency** | 0-2s | < 100ms |
| **Network** | High (headers every 2s) | Low (connection reuse) |
| **Server Connections** | N users = N requests/min | N users = N persistent connections |
| **Database Load** | High (M queries/min per user) | Low (only on webhook) |
| **Implementation** | Simple | Complex (connection mgmt, reconnect) |
| **Browser Support** | All | Modern only |
| **Infrastructure** | Stateless (scales easily) | Stateful (affinity needed) |
| **Cost (AWS ALB)** | Cheap | More expensive (connection mgmt) |

**When to Switch:**

- **Polling is fine if:**
  - < 1000 concurrent users
  - Status updates not time-critical
  - Mobile app (battery drain from constant polling)

- **WebSocket needed if:**
  - > 10k concurrent users
  - Need real-time notifications (< 1s)
  - Mobile app demanding low latency

**WebSocket Implementation (if needed):**

```ruby
# Backend: Rails + ActionCable

class MessagesChannel < ApplicationCable::Channel
  def subscribed
    current_user = User.find(decoded_token['user_id'])
    stream_for current_user
  end

  def unsubscribed
    # Clean up
  end
end

# In webhook handler:
webhook_payload = params[:MessageSid]
message = Message.find_by(twilio_sid: webhook_payload)
user = message.user

# Broadcast to user's WebSocket
MessagesChannel.broadcast_to(user, {
  type: 'status_updated',
  message_id: message.id,
  status: message.status
})

# Frontend: Angular
const ws = new WebSocket(
  'wss://api.myapp.com/cable?token=' + token
)

ws.onmessage = (event) => {
  const { type, message_id, status } = JSON.parse(event.data)
  if (type === 'status_updated') {
    this.updateMessageStatus(message_id, status)
  }
}
```

**Scaling WebSockets:**

```ruby
# Problem: WebSocket server is stateful
# 10 servers, user connects to server #3, 
# webhook handler on server #7 can't push to user

# Solution: Pub/Sub + Redis

# Each server subscribes to user's channel in Redis
class MessagesChannel
  def subscribed
    user = current_user
    redis = Redis.new
    
    # Subscribe to Redis channel
    redis.subscribe("user:#{user.id}:messages") do |on|
      on.message do |channel, data|
        transmit JSON.parse(data)
      end
    end
  end
end

# Webhook handler (any server):
user = message.user
redis = Redis.new
redis.publish("user:#{user.id}:messages", {
  type: 'status_updated',
  message_id: message.id,
  status: message.status
}.to_json)

# Result: Message published to Redis channel
# All servers listening to that channel receive it
# Their WebSocket connections transmit to frontend
```

**Recommendation:**
- **Start with polling** (current approach is fine for < 10k users)
- **Switch to WebSocket when:**
  - User growth demands it (> 10k concurrent)
  - OR: Business requires real-time (< 1s) notifications
  - Cost of real-time justifies complexity

---

## 12. Session Validation Strategy on App Initialization



**Problem Statement:**

When a frontend app loads and finds a stored token (in localStorage, sessionStorage, or cookies):
- Token might be expired
- Token might be revoked (user logged out from another device)
- Backend state might have changed (user deleted, permissions revoked)
- Simply trusting stored tokens creates security risk

**Four Common Approaches:**

### Approach 1: JWT-Only (Self-Validating) ❌
```typescript
// Check token exists and isn't locally expired
if (storedToken && !isExpired(storedToken)) {
  setLoggedIn(true);
  // Don't call backend
}
```

**Pros:**
- Zero server calls on init
- Fastest app startup
- Stateless (no backend session store needed)

**Cons:**
- ❌ Can't detect revoked tokens (user logged out from another device)
- ❌ Can't detect permission changes
- ❌ Your original issue: session never truly expires
- ❌ If backend revokes token, client won't know until token actually expires
- ❌ High security risk for critical apps

**When to use:** Low-risk features (analytics, public content), development

---

### Approach 2: Refresh Token + Call /Me (What I Implemented) ⭐ Good for Security
```typescript
// On app init
if (accessToken) {
  // Option A: Try to refresh (preferred for stateful sessions)
  // Option B: Validate with /me (implemented in this app)
  validateWithBackend();  // GET /me (returns 401 if token invalid)
}

// GET /me endpoint
Backend validates access token signature and state
Returns 200 { user: {...} } if valid
Returns 401 if expired/revoked/invalid
```

**Pros:**
- ✅ Detects revoked tokens immediately
- ✅ Detects permission changes
- ✅ Always synced with backend state
- ✅ Secure: backend has final say

**Cons:**
- Extra HTTP request on every app load
- User sees loading state during validation
- Doesn't extend session (user re-authenticates after expiry)
- If /me is slow, app load is slow

**When to use:** Security-critical apps (banking, messaging, healthcare)

**Latency Impact:**
- /me endpoint: ~50-200ms (database query)
- Total app init: +50-200ms to first render
- Acceptable for most UX (users expect ~1-2s load)

---

### Approach 3: Refresh Token Pattern (Industry Standard) ✅ Best Overall
```typescript
// On app init
if (refreshToken) {
  try {
    newAccessToken = await POST /refresh { refreshToken }
    // Backend validates refresh token, issues new access token
    // If refresh fails (401), redirect to login
  } catch (err) {
    if (err.status === 401) {
      redirectToLogin();  // Refresh token expired
    }
  }
}
// Then call /me if needed to get user details
```

**Token Flow:**
```
Login:
  POST /login → issues access_token (15-min) + refresh_token (7-day)

App Init:
  Refresh Token exists?
    YES → POST /refresh → get new access_token (extends session)
    NO → redirect to login

Request:
  GET /api/messages + access_token
  Access token expired?
    YES → POST /refresh → get new access_token → retry request
    NO → proceed

Logout:
  DELETE /logout → increment refresh_token version → redirect to login
```

**Pros:**
- ✅ Industry standard (used by Google, GitHub, AWS, Facebook)
- ✅ Automatically extends sessions (user stays logged in)
- ✅ Detects revoked tokens (version mismatch on refresh)
- ✅ Short-lived access tokens (15-60 min) = safer
- ✅ Long-lived refresh tokens (7-30 days) = better UX
- ✅ Single HTTP call on init (refresh), not validation
- ✅ Can auto-retry requests with new token

**Cons:**
- More complex (2 tokens, refresh endpoint, retry logic)
- Need token versioning in database (for revocation)
- Refresh token needs httpOnly cookie (not localStorage)

**When to use:** Most production apps (you should migrate to this)

---

### Approach 4: Server-Side Sessions (Traditional)
```
Login:
  POST /login → create session in database
  Set Set-Cookie: session_id=<uuid>; HttpOnly; Secure

App Init:
  Browser automatically sends session_id cookie
  First request: GET /messages + session_id cookie
  Backend validates session exists in database
  No special init logic needed (implicit via cookies)

Logout:
  DELETE /logout → delete session from database
  Set-Cookie: session_id=; Max-Age=0
```

**Pros:**
- ✅ Simplest for SPAs (browser handles cookies automatically)
- ✅ Server has full control (can revoke instantly)
- ✅ No need for refresh token logic

**Cons:**
- ❌ Requires database lookup on every request (slower)
- ❌ Doesn't scale without distributed session store (Redis)
- ❌ Not ideal for mobile/APIs (cookies are browser-specific)
- ❌ CSRF risk (though mitigated with SameSite)

**When to use:** Traditional server-rendered apps, high security requirement

---

## Comparison Table

| Approach | Init Calls | Detect Revoked | Session Extends | Complexity | Latency | Security |
|----------|-----------|----------------|-----------------|-----------|---------|----------|
| **JWT-Only** | 0 | ❌ No | ❌ No | Low | Fast | Low |
| **Validate /me** | 1 | ✅ Yes | ❌ No | Medium | +50-200ms | High |
| **Refresh Token** | 1 | ✅ Yes | ✅ Yes | High | +50-100ms | Highest |
| **Server Sessions** | 1 | ✅ Yes | ✅ Yes | Medium | +10-50ms* | High |

*Depends on session store (Redis vs. Database)

---

## Recommendation & Migration Path

**Current Implementation (Validate /me):**
- ✅ Good for security
- ⚠️ Doesn't extend sessions (issue you reported)
- ⚠️ Extra init latency

**Migration Path:**

**Phase 1 (Now):** Keep /me validation
- Immediate security fix
- Detects revoked tokens
- Documented for interview

**Phase 2 (3 months):** Add Refresh Token Pattern
- Backend: implement /refresh endpoint with token versioning
- Frontend: use refresh token on init instead of /me
- Auto-retry failed requests with new token

**Phase 3 (6 months):** Store tokens in httpOnly cookies
- Migrate from localStorage to cookies (backend sets via Set-Cookie)
- Removes XSS vulnerability
- Browser handles token sending automatically

**Code Changes for Phase 2:**

Backend:
```ruby
# app/controllers/sessions_controller.rb
def refresh
  token = decode_jwt(request.cookies[:refresh_token])
  user = User.find(token.user_id)
  
  # Check if token was revoked (version mismatch)
  if user.refresh_token_version != token.version
    return 401  # Token revoked on another device
  end
  
  # Issue new access token
  new_access_token = generate_jwt(user, expires_in: 15.minutes)
  set_auth_cookie(:access_token, new_access_token)
  render json: { user: user }
end
```

Frontend:
```typescript
// auth.service.ts
private async initializeAuth(): Promise<void> {
  const refreshToken = this.tokenStorage.getRefreshToken();
  
  if (refreshToken) {
    try {
      // Try to get new access token
      const response = await this.http.post('/refresh', {}).toPromise();
      // Backend sets new access_token cookie automatically
      this.currentUser.set(response.user);
      this.isLoggedIn.set(true);
    } catch (error) {
      if (error.status === 401) {
        // Refresh token expired or revoked
        this.clearAuth();
        this.router.navigate(['/login']);
      }
    }
  }
  this.isInitialized.set(true);
}
```

---

## Implementation Decision for This App

**Chosen Approach: Validate with /me endpoint (Approach 2)**

**Why:**
1. Quick security fix for the reported issue (session persisting after backend restart)
2. Medium complexity (good for interview demonstration)
3. Immediately detects revoked tokens
4. Can be upgraded to Refresh Token pattern later

**Trade-offs Accepted:**
- ⚠️ Extra 50-200ms on app init (acceptable)
- ⚠️ Sessions don't auto-extend (users re-authenticate after token expiry)
- ✅ Secure: backend has final say on validity
- ✅ Fixes the core issue: stale tokens are rejected

**Future Improvement (Phase 2):**
- Implement /refresh endpoint with token versioning
- Migrate to refresh token pattern
- Extend sessions to 7+ days with auto-refresh

---

## Summary Table: Evolution by Scale

| Stage | Users | Messages/sec | Architecture Changes |
|-------|-------|--------------|----------------------|
| **Current** | < 1k | < 10 | Single Rails server, local MongoDB, polling, no pagination |
| **Stage 1** | 1-10k | 10-100 | Add Sidekiq for async sending, cursor-based pagination, basic monitoring |
| **Stage 2** | 10-100k | 100-1k | Horizontal scaling, MongoDB sharding by user_id, cache stats (not messages), add caching (Redis) |
| **Stage 3** | 100k-1M | 1k-10k | Kafka for webhooks, multi-region, real-time WebSocket, CQRS for heavy reads |
| **Stage 4** | 1M+ | 10k+ | Distributed databases, edge servers, complex routing, separate read/write optimization |

---

## Key Takeaways

1. **Database**: MongoDB with sharding by user_id scales well for this use case
2. **Read/Write Separation**: Progression is Single DB → Read Replicas → CQRS → Separate DBs
   - Start with replicas at 10k users (simple, low cost)
   - Only CQRS if reads are proven bottleneck at 100k users
   - Measure first: bottleneck is usually N+1 queries or bad indexes, not throughput
3. **Pagination**: Cursor-based (not offset) for messages; enables fast queries at any scale
4. **Caching**: Don't cache volatile messages; cache stats + user metadata instead
5. **Query Optimization**: Indexing + projection + connection pooling beat caching for read queries
6. **Async**: Introduce job queues (Sidekiq) once latency becomes an issue
7. **Webhooks**: Buffer in Redis, batch process to reduce database load
8. **Auth**: JWT in httpOnly cookies, refresh tokens, token versioning for revocation
9. **Rate Limiting**: Multi-layer (IP, user, recipient, plan)
10. **Real-Time**: Polling is fine until 10k+ users; then consider WebSocket
11. **Reliability**: Retry logic + idempotency keys prevent duplicate messages
12. **Monitoring**: APM is critical—track delivery rate, webhook latency, query performance, response times
13. **Session Validation**: Validate tokens with /me endpoint on app init (security-first approach); migrate to refresh token pattern for production

## Interview Topics Covered (12 Questions)

1. ✅ Database Scaling & Sharding Strategy
2. ✅ Indexing & Query Optimization  
3. ✅ Message Queues & Async Processing
4. ✅ Real-Time Webhook Handling
5. ✅ Failure Recovery & SLAs
6. ✅ Security & Token Management
7. ✅ Rate Limiting & DDoS Protection
8. ✅ **Pagination for Large Datasets** ← cursor-based approach
9. ✅ **Caching Strategy for Read Performance** ← when to cache vs. optimize queries
10. ✅ **Read/Write Database Separation** ← replicas vs. CQRS vs. separate DBs
11. ✅ WebSocket vs. Polling Trade-offs
12. ✅ **Session Validation on App Init** ← JWT-only vs. /me vs. refresh tokens vs. server sessions

---

**Document Generated**: October 6, 2026  
**Prepared for**: Senior Software Engineer Interview  
**App**: MySMS Messenger
