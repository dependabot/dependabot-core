# typed: strict
# frozen_string_literal: true

$LOAD_PATH.unshift(__dir__ + "/../lib")

$stdout.sync = true

require "dependabot/api_client"
require "dependabot/environment"
require "dependabot/fetched_files"
require "dependabot/service"
require "dependabot/setup"
require "dependabot/file_fetcher_command"
require "dependabot/update_files_command"
require "debug" if ENV["DEBUG"]

flamegraph = ENV.fetch("FLAMEGRAPH", nil)
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
  # Under isolate_fetch_update the fetch container has already cloned and persisted the
  # files to DEPENDABOT_OUTPUT_PATH, so we rehydrate them here instead of cloning again.
  job_config = Dependabot::Environment.job_definition["job"]
  job_experiments = job_config.is_a?(Hash) ? job_config["experiments"] : nil
  isolate_fetch_update =
    job_experiments.is_a?(Hash) &&
    job_experiments.any? { |name, value| name.to_s.tr("-", "_") == "isolate_fetch_update" && value }

  fetched_files =
    if isolate_fetch_update
      # The fetch container staged the file tree on the shared volume. Re-run the file fetcher
      # against the staged tree (no cloning or network) so all file metadata is recomputed
      # authentically, using the base commit SHA supplied in the job definition.
      base_commit_sha = Dependabot::Environment.job_definition["base_commit_sha"]
      raise "base_commit_sha missing from job definition" unless base_commit_sha.is_a?(String)

      Dependabot::FileFetcherCommand.new.fetch_from_staged_files(base_commit_sha: base_commit_sha)
    else
      fetcher = Dependabot::FileFetcherCommand.new
      fetcher.run
      fetcher.files
    end

  if flamegraph
    Flamegraph.generate("/tmp/dependabot-flamegraph.html") do
      Dependabot::UpdateFilesCommand.new(fetched_files).run
    end
  else
    Dependabot::UpdateFilesCommand.new(fetched_files).run
  end
rescue Dependabot::RunFailure
  exit 1
end
