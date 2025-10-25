ENV["RAILS_ENV"] ||= "test"

# Module to suppress unwanted output during tests
module TestOutputSuppression
  def system(*args)
    if ENV['RAILS_ENV'] == 'test' && !ENV['VERBOSE_TESTS']
      # Suppress system command output during tests
      super(*args, out: File::NULL, err: File::NULL)
    else
      super(*args)
    end
  end
end

# Only apply output suppression in test environment
if ENV['RAILS_ENV'] == 'test'
  Object.prepend(TestOutputSuppression)
end

# Start SimpleCov for code coverage
require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/test/'
  add_filter '/config/'
  add_filter '/vendor/'
  
  add_group 'Models', 'app/models'
  add_group 'Controllers', 'app/controllers'
  add_group 'Helpers', 'app/helpers'
  add_group 'Channels', 'app/channels'
  add_group 'Jobs', 'app/jobs'
  add_group 'Mailers', 'app/mailers'
  add_group 'Concerns', 'app/controllers/concerns'
  add_group 'Model Concerns', 'app/models/concerns'
end

require_relative "../config/environment"
require "rails/test_help"

# Clean up static files that might interfere with routing
File.delete('public/index.html') if File.exist?('public/index.html')

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
  
  # Helper to suppress stdout during operations that produce unwanted output
  def suppress_stdout
    original_stdout = $stdout
    $stdout = File.open(File::NULL, "w")
    yield
  ensure
    $stdout = original_stdout
  end
end
