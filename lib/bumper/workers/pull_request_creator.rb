require "hutch"
$LOAD_PATH << "lib"

$stdout.sync = true

require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/pull_request_creator"

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
