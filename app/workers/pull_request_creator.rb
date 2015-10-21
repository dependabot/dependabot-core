require "shoryuken"
require "./app/boot"
require "./app/dependency"
require "./app/dependency_file"
require "./app/pull_request_creator"

$stdout.sync = true

module Workers
  class PullRequestCreator
    include Shoryuken::Worker

    shoryuken_options(
      queue: "bump-updated_dependency_files",
      body_parser: :json,
      auto_delete: true,
      retry_intervals: [60, 300, 3_600, 36_000] # specified in seconds
    )

    def perform(_sqs_message, body)
      updated_dependency = Dependency.new(
        name: body["updated_dependency"]["name"],
        version: body["updated_dependency"]["version"]
      )

      updated_dependency_files = body["updated_dependency_files"].map do |file|
        DependencyFile.new(name: file["name"], content: file["content"])
      end

      pull_request_creator = ::PullRequestCreator.new(
        repo: body["repo"]["name"],
        dependency: updated_dependency,
        files: updated_dependency_files
      )

      pull_request_creator.create
    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
    end
  end
end
