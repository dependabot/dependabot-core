# frozen_string_literal: true
require "rspec/its"
require "webmock/rspec"

RSpec.configure do |config|
  config.color = true
  config.order = :rand
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

def fixture(*name)
  File.read(File.join("spec", "fixtures", File.join(*name)))
end

def capture_stderr
  previous_stderr = $stderr
  $stderr = StringIO.new
  yield
ensure
  $stderr = previous_stderr
end
