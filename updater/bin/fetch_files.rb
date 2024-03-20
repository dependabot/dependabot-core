# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

$LOAD_PATH.unshift(T.must(__dir__) + "/../lib")

$stdout.sync = true

require "dependabot/api_client"
require "dependabot/environment"
require "dependabot/service"
require "dependabot/setup"
require "dependabot/file_fetcher_command"
require "debug" if ENV["DEBUG"]

class UpdaterKilledError < StandardError; end

trap("TERM") do
  puts "Received SIGTERM"
  error = UpdaterKilledError.new("Updater process killed with SIGTERM")
  tags = { "gh.dependabot_api.update_job.id": ENV.fetch("DEPENDABOT_JOB_ID", nil) }

  api_client =
    Dependabot::ApiClient.new(
      Dependabot::Environment.api_url,
      Dependabot::Environment.job_id,
      Dependabot::Environment.job_token
    )
  Dependabot::Service.new(client: api_client).capture_exception(error: error, tags: tags)
  exit
end

begin
  Dependabot::FileFetcherCommand.new.run
rescue Dependabot::RunFailure
  exit 1
end
