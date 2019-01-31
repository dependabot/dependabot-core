# frozen_string_literal: true

require "rspec/its"
require "webmock/rspec"
require "vcr"
require "byebug"

require_relative "dummy_package_manager/metadata_finder"
require_relative "dummy_package_manager/version"
require_relative "dummy_package_manager/requirement"

RSpec.configure do |config|
  config.color = true
  config.order = :rand
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Prevent access tokens being written to VCR cassettes
  unless ENV["DEPENDABOT_TEST_ACCESS_TOKEN"].nil?
    config.filter_sensitive_data("<TOKEN>") do
      ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]
    end
  end

  # Let's you set default VCR mode with VCR=all for re-recording
  # episodes. :once is VCR default
  record_mode = ENV["VCR"] ? ENV["VCR"].to_sym : :once
  config.default_cassette_options = { record: record_mode }
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

# Spec helper to provide GitHub credentials if set via an environment variable
def github_credentials
  if ENV["DEPENDABOT_TEST_ACCESS_TOKEN"].nil?
    []
  else
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]
    }]
  end
end
