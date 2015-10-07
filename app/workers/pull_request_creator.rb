require "hutch"
require "./app/boot"
require "./app/dependency"
require "./app/dependency_file"
require "./app/pull_request_creator"

$stdout.sync = true

module Workers
  class PullRequestCreator
    include Hutch::Consumer
    consume "bump.updated_files_to_create_pr_for"

    def process(body)
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
      Raven.capture_exception(error)
      raise
    end
  end
end
