require 'test_helper'

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_a = create_user('alice@example.com', 'password123')
    @user_b = create_user('bob@example.com', 'password123')

    # Create messages for user A
    @msg_a1 = create_message(@user_a, '+15551234567', 'Hello from Alice 1')
    @msg_a2 = create_message(@user_a, '+15559876543', 'Hello from Alice 2')

    # Create messages for user B
    @msg_b1 = create_message(@user_b, '+15558888888', 'Hello from Bob 1')
    @msg_b2 = create_message(@user_b, '+15557777777', 'Hello from Bob 2')
  end

  # ==================== DATA ISOLATION TESTS ====================

  test "user A cannot see user B's messages" do
    # Log in as user A
    login(@user_a)

    # Fetch messages as user A
    get '/messages'
    assert_response :success

    messages = JSON.parse(@response.body)
    message_ids = messages.map { |m| m['id'] }

    # User A should only see their own messages
    assert_includes message_ids, @msg_a1.id.to_s, "User A should see their own message 1"
    assert_includes message_ids, @msg_a2.id.to_s, "User A should see their own message 2"

    # User A should NOT see user B's messages
    assert_not_includes message_ids, @msg_b1.id.to_s, "User A should NOT see user B's message 1"
    assert_not_includes message_ids, @msg_b2.id.to_s, "User A should NOT see user B's message 2"

    # Verify count is exactly 2
    assert_equal 2, messages.length, "User A should see exactly 2 messages"
  end

  test "user B cannot see user A's messages" do
    # Log in as user B
    login(@user_b)

    # Fetch messages as user B
    get '/messages'
    assert_response :success

    messages = JSON.parse(@response.body)
    message_ids = messages.map { |m| m['id'] }

    # User B should only see their own messages
    assert_includes message_ids, @msg_b1.id.to_s, "User B should see their own message 1"
    assert_includes message_ids, @msg_b2.id.to_s, "User B should see their own message 2"

    # User B should NOT see user A's messages
    assert_not_includes message_ids, @msg_a1.id.to_s, "User B should NOT see user A's message 1"
    assert_not_includes message_ids, @msg_a2.id.to_s, "User B should NOT see user A's message 2"

    # Verify count is exactly 2
    assert_equal 2, messages.length, "User B should see exactly 2 messages"
  end

  test "unauthenticated user gets 401 error" do
    get '/messages'
    assert_response :unauthorized, "Unauthenticated user should get 401"
  end

  test "user cannot create messages for another user" do
    # Log in as user A
    login(@user_a)

    # Even if we try to send a message, it gets user_a's ID
    post '/messages', params: {
      message: { to: '+15551234567', body: 'Sneaky message' }
    }
    assert_response :created

    # The message should belong to user A
    created_message = Message.order(:created_at).last
    assert_equal @user_a.id, created_message.user_id, "Message must belong to user A, not spoofed"

    # User B should NOT see it
    login(@user_b)
    get '/messages'
    messages = JSON.parse(@response.body)
    message_ids = messages.map { |m| m['id'] }

    assert_not_includes message_ids, created_message.id.to_s, "User B should not see user A's new message"
  end

  test "message count is correct per user" do
    # User A has 2 messages
    login(@user_a)
    get '/messages'
    assert_response :success
    messages_a = JSON.parse(@response.body)
    assert_equal 2, messages_a.length, "User A should have 2 messages"

    # User B has 2 messages
    login(@user_b)
    get '/messages'
    assert_response :success
    messages_b = JSON.parse(@response.body)
    assert_equal 2, messages_b.length, "User B should have 2 messages"

    # Total in DB is 4
    assert_equal 4, Message.count, "Total messages in DB should be 4"
  end

  # ==================== HELPER METHODS ====================

  private

  def create_user(email, password)
    User.create!(
      email: email,
      password: password,
      password_confirmation: password
    )
  end

  def create_message(user, phone, body)
    Message.create!(
      user_id: user.id,
      to: phone,
      body: body,
      status: 'queued'
    )
  end

  def login(user)
    post '/login', params: {
      user: {
        email: user.email,
        password: 'password123'
      }
    }
    assert_response :success, "Login failed for #{user.email}"
  end
end
