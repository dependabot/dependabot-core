# typed: false
# frozen_string_literal: true

require "dependabot/logger"
require "logger"
require "rspec/sorbet"
require "vcr"
require "webmock/rspec"
require "yaml"

# TODO: Stop rescuing StandardError in Dependabot::BaseCommand#run
#
# For now we log errors as these can surface exceptions that currently get rescued
# in integration tests.
#
# This includes missing VCR fixtures.
Dependabot.logger = Logger.new($stdout, level: Logger::ERROR)

WebMock.disable_net_connect!

# Set git envvars so we can commit to repos during test setup if required
ENV["GIT_AUTHOR_NAME"] = "dependabot-ci"
ENV["GIT_AUTHOR_EMAIL"] = "no-reply@github.com"
ENV["GIT_COMMITTER_NAME"] = "dependabot-ci"
ENV["GIT_COMMITTER_EMAIL"] = "no-reply@github.com"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.profile_examples = 10
  config.order = :random

  Kernel.srand config.seed

  def fixture(path)
    File.read(File.join("spec", "fixtures", path))
  end

  def job_definition_fixture(path)
    YAML.load(
      fixture(File.join("job_definitions", "#{path}.yaml"))
    )
  end
end

RSpec::Sorbet.allow_doubles!

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.allow_http_connections_when_no_cassette = false

  config.filter_sensitive_data("<AWS_ACCESS_KEY_ID>") do
    ENV.fetch("AWS_ACCESS_KEY_ID", nil)
  end

  config.filter_sensitive_data("<AWS_SECRET_ACCESS_KEY>") do
    ENV.fetch("AWS_SECRET_ACCESS_KEY", nil)
  end

  config.filter_sensitive_data("<AUTHORIZATION>") do |interaction|
    interaction.request.headers["Authorization"]&.first
  end

  # Prevent access tokens being written to VCR cassettes
  unless ENV["DEPENDABOT_TEST_ACCESS_TOKEN"].nil?
    config.filter_sensitive_data("<TOKEN>") do
      ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]
    end
  end

  # Let's you set default VCR mode with VCR=all for re-recording
  # episodes. :once is VCR default
  record_mode = ENV["VCR"] ? ENV["VCR"].to_sym : :none
  config.default_cassette_options = {
    record: record_mode,
    allow_unused_http_interactions: false
  }
end

def test_access_token
  ENV.fetch("DEPENDABOT_TEST_ACCESS_TOKEN", "missing-test-access-token")
end
