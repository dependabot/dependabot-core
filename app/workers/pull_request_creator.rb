require "sidekiq"
require "./app/boot"
require "./app/dependency"
require "./app/dependency_file"
require "./app/pull_request_creator"

$stdout.sync = true

module Workers
  class PullRequestCreator
    include Sidekiq::Worker

    sidekiq_options queue: "bump-updated_dependency_files", retry: 4

    sidekiq_retry_in { |count| [60, 300, 3_600, 36_000][count] }

    def perform(body)
      updated_dependency = Dependency.new(
        name: body["updated_dependency"]["name"],
        version: body["updated_dependency"]["version"],
        language: body["repo"]["language"]
      )

      updated_dependency_files = body["updated_dependency_files"].map do |file|
        DependencyFile.new(name: file["name"], content: file["content"])
      end

      pull_request_creator = ::PullRequestCreator.new(
        repo: body["repo"]["name"],
        base_commit: body["repo"]["commit"],
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
