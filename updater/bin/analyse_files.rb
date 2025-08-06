# typed: strict
# frozen_string_literal: true

$LOAD_PATH.unshift(__dir__ + "/../lib")

$stdout.sync = true

require "dependabot/api_client"
require "dependabot/environment"
require "dependabot/service"
require "dependabot/setup"
require "dependabot/analyse_files_command"
require "debug" if ENV["DEBUG"]

flamegraph = ENV.fetch("FLAMEGRAPH", nil)
if flamegraph
  require "stackprof"
  require "flamegraph"
end

class AnalysisKilledError < StandardError; end

trap("TERM") do
  puts "Received SIGTERM"
  error = AnalysisKilledError.new("Analysis process killed with SIGTERM")
  # TODO(brrygrdn): Confirm a separate id sequence for Analysis jobs
  #
  # The current proposal is that analysis jobs should use their own sequence, so we
  # need to avoid polluting the `gh.dependabot_api.update_job.id` tag with two sequences.
  #
  # The trade off is that analysis jobs will use observability faceted on this tag instead.
  #
  tags = { "gh.dependabot_api.analysis_job.id": ENV.fetch("DEPENDABOT_JOB_ID", nil) }

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
    Flamegraph.generate("/tmp/dependabot-flamegraph.html") do
      Dependabot::AnalyseFilesCommand.new.run
    end
  else
    Dependabot::AnalyseFilesCommand.new.run
  end
rescue Dependabot::RunFailure
  exit 1
end
