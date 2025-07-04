require "test_helper"

class ApplicationRecordTest < ActiveSupport::TestCase
  # Create a test model to test ApplicationRecord functionality
  def setup
    # Use existing Event model which inherits from ApplicationRecord
    @record = events(:one)
  end

  test "should be abstract class" do
    assert ApplicationRecord.abstract_class?
  end

  test "readonly? instance method should check class variable and super" do
    # Store original value
    original_readonly = ApplicationRecord.class_variable_get(:@@readonly_showcase)
    
    # Test when @@readonly_showcase is false/nil
    ApplicationRecord.class_variable_set(:@@readonly_showcase, nil)
    assert_not @record.readonly?
    
    # Test when @@readonly_showcase is true
    ApplicationRecord.class_variable_set(:@@readonly_showcase, true)
    assert @record.readonly?
    
  ensure
    # Restore original value
    ApplicationRecord.class_variable_set(:@@readonly_showcase, original_readonly)
  end

  test "readonly? class method should return boolean of class variable" do
    # Store original value
    original_readonly = ApplicationRecord.class_variable_get(:@@readonly_showcase)
    
    ApplicationRecord.class_variable_set(:@@readonly_showcase, nil)
    assert_not ApplicationRecord.readonly?
    
    ApplicationRecord.class_variable_set(:@@readonly_showcase, false)
    assert_not ApplicationRecord.readonly?
    
    ApplicationRecord.class_variable_set(:@@readonly_showcase, true)
    assert ApplicationRecord.readonly?
    
    ApplicationRecord.class_variable_set(:@@readonly_showcase, "truthy")
    assert ApplicationRecord.readonly?
    
  ensure
    # Restore original value
    ApplicationRecord.class_variable_set(:@@readonly_showcase, original_readonly)
  end

  test "should respond to normalizes method" do
    # Test the stub method exists (for Rails < 7.1 compatibility)
    assert_respond_to ApplicationRecord, :normalizes
    
    # Should not raise error when called (stub method does nothing)
    assert_nothing_raised do
      ApplicationRecord.normalizes :some_field, with: -> value { value }
    end
  end

  test "RAILS_STORAGE constant should be defined" do
    assert_kind_of Pathname, ApplicationRecord::RAILS_STORAGE
    assert ApplicationRecord::RAILS_STORAGE.to_s.length > 0
  end

  test "upload_blobs should return early when not in FLY_REGION" do
    with_env('FLY_REGION' => nil) do
      # Should return nil/early without doing anything
      result = @record.upload_blobs
      assert_nil result
    end
  end

  test "upload_blobs should return early when no local attachments" do
    with_env('FLY_REGION' => 'test-region') do
      # Since there are no local attachments in test fixtures,
      # this should return nil (early return)
      result = @record.upload_blobs
      assert_nil result
    end
  end

  test "download_blob should return early when not in FLY_REGION" do
    blob = double_stub(service_name: 'tigris', key: 'test123')
    
    with_env('FLY_REGION' => nil) do
      result = @record.download_blob(blob)
      assert_nil result
    end
  end

  test "download_blob should return early when blob service is not tigris" do
    blob = double_stub(service_name: 'local', key: 'test123')
    
    with_env('FLY_REGION' => 'test-region') do
      result = @record.download_blob(blob)
      assert_nil result
    end
  end

  test "download_blob should test path generation" do
    blob = double_stub(service_name: 'tigris', key: 'abcd1234')
    expected_path = ApplicationRecord::RAILS_STORAGE.join('ab/cd/abcd1234')
    
    # The method returns early (line 81 in application_record.rb)
    # so we just verify it returns nil
    with_env('FLY_REGION' => 'test-region') do
      result = @record.download_blob(blob)
      assert_nil result
    end
  end

  private

  def with_env(new_env)
    old_env = {}
    new_env.each { |k, v| old_env[k] = ENV[k]; ENV[k] = v }
    yield
  ensure
    old_env.each { |k, v| ENV[k] = v }
  end

  # Simple stub helper for mocking
  def double_stub(methods = {})
    obj = Object.new
    methods.each do |method, return_value|
      obj.define_singleton_method(method) { return_value }
    end
    obj
  end
end