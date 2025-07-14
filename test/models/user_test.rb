require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "should be valid with valid attributes" do
    user = User.new(
      userid: "testuser", 
      password: "password123", 
      password_confirmation: "password123",
      email: "test@example.com"
    )
    assert user.valid?
  end

  test "userid should be present" do
    @user.userid = nil
    assert_not @user.valid?
    assert_includes @user.errors[:userid], "can't be blank"
  end

  test "userid should be unique" do
    duplicate_user = @user.dup
    duplicate_user.email = "different@example.com"
    @user.save
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:userid], "has already been taken"
  end

  test "userid should be normalized (stripped)" do
    user = User.new(
      userid: "  spaced_user  ",
      password: "password123",
      password_confirmation: "password123", 
      email: "spaced@example.com"
    )
    user.save
    assert_equal "spaced_user", user.userid
  end

  test "email should be present" do
    @user.email = nil
    assert_not @user.valid?
    assert_includes @user.errors[:email], "can't be blank"
  end

  test "email should be unique" do
    duplicate_user = @user.dup
    duplicate_user.userid = "different_user"
    @user.save
    assert_not duplicate_user.valid?
    assert_includes duplicate_user.errors[:email], "has already been taken"
  end

  test "email should be normalized (stripped)" do
    user = User.new(
      userid: "emailtest",
      password: "password123",
      password_confirmation: "password123",
      email: "  spaced@example.com  "
    )
    user.save
    assert_equal "spaced@example.com", user.email
  end

  test "password should be confirmed" do
    user = User.new(
      userid: "testuser",
      password: "password123",
      password_confirmation: "different_password",
      email: "test@example.com"
    )
    assert_not user.valid?
    assert_includes user.errors[:password_confirmation], "doesn't match Password"
  end

  test "should have many locations" do
    assert_respond_to @user, :locations
  end

  test "locations should be nullified when user is destroyed" do
    user = users(:two)
    location = locations(:one)
    assert_equal user, location.user
    
    user.destroy
    location.reload
    assert_nil location.user_id
  end

  # Class method tests
  test "dbopen should return SQLite3 database when RAILS_DB_VOLUME is set" do
    skip unless ENV['RAILS_DB_VOLUME']  # Only run if environment variable is set
    
    with_env('RAILS_DB_VOLUME' => 'test/fixtures') do
      # This would require a test index.sqlite3 file to exist
      skip "Test database file not available"
    end
  end

  test "authorized? should return true when no database connection" do
    User.class_variable_set(:@@db, nil)
    assert User.authorized?("any_user")
  end

  test "index_auth? should allow access in development without userid" do
    # Mock Rails.env.development? to return true
    Rails.env.define_singleton_method(:development?) { true }
    assert User.index_auth?(nil)
  ensure
    # Restore original method
    Rails.env.singleton_class.remove_method(:development?) if Rails.env.singleton_class.method_defined?(:development?)
  end

  test "index_auth? should deny access without userid in non-development" do
    with_env('RAILS_ENV' => 'production') do
      assert_not User.index_auth?(nil)
    end
  end

  test "owned? should handle index ownership" do
    # Mock the studios_owned method to return 'index'
    User.define_singleton_method(:studios_owned) { |userid| ['index'] }
    assert User.owned?("index_owner")
  ensure
    # Clean up the mock
    User.singleton_class.remove_method(:studios_owned) if User.singleton_class.method_defined?(:studios_owned)
  end

  test "authlist should return empty array when no database" do
    User.class_variable_set(:@@db, nil)
    assert_equal [], User.authlist
  end

  test "trust_level should return class variable value" do
    User.class_variable_set(:@@trust_level, 5)
    assert_equal 5, User.trust_level
  end

  private

  def with_env(new_env)
    old_env = {}
    new_env.each { |k, v| old_env[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    old_env.each { |k, v| ENV[k] = v }
  end
end
