# typed: false
# frozen_string_literal: true

$LOAD_PATH.unshift(__dir__ + "/../lib")

$stdout.sync = true

require "dependabot/api_client"
require "dependabot/environment"
require "dependabot/service"
require "dependabot/setup"
require "dependabot/update_files_command"
require "debug" if ENV["DEBUG"]

flamegraph = ENV["FLAMEGRAPH"]
if flamegraph
  require "stackprof"
  require "flamegraph"
end

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
  if flamegraph
    Flamegraph.generate('/tmp/dependabot-flamegraph.html') do
      Dependabot::UpdateFilesCommand.new.run
    end
  else
    Dependabot::UpdateFilesCommand.new.run
  end
rescue Dependabot::RunFailure
  exit 1
end
