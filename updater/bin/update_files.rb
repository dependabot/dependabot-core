# typed: strict
# frozen_string_literal: true

$LOAD_PATH.unshift(__dir__ + "/../lib")

$stdout.sync = true

require "dependabot/api_client"
require "dependabot/dependency_file"
require "dependabot/environment"
require "dependabot/fetched_files"
require "dependabot/service"
require "dependabot/setup"
require "dependabot/file_fetcher_command"
require "dependabot/update_files_command"
require "base64"
require "json"
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
      # The fetch container wrote each file's content to the shared volume and a metadata-only
      # manifest to the output path. Rebuild the DependencyFile objects by reading the content
      # back from disk and combining it with the manifest metadata.
      manifest = JSON.parse(File.read(Dependabot::Environment.output_path))
      dependency_files = manifest.fetch("dependency_files").map do |attributes|
        path = attributes.fetch("dependency_file_path")
        raw = File.binread(path)
        content =
          if attributes["content_encoding"] == Dependabot::DependencyFile::ContentEncoding::BASE64
            Base64.encode64(raw)
          else
            raw.force_encoding(Encoding::UTF_8)
          end
        Dependabot::DependencyFile.new(
          name: attributes.fetch("name"),
          content: content,
          directory: attributes.fetch("directory"),
          type: attributes.fetch("type"),
          support_file: attributes.fetch("support_file"),
          vendored_file: attributes.fetch("vendored_file"),
          symlink_target: attributes["symlink_target"],
          content_encoding: attributes.fetch("content_encoding"),
          operation: attributes.fetch("operation"),
          mode: attributes["mode"],
          dependency_file_path: path
        )
      end
      Dependabot::FetchedFiles.new(
        dependency_files: dependency_files,
        base_commit_sha: manifest.fetch("base_commit_sha")
      )
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
