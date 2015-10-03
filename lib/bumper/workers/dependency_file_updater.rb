require "shoryuken"
require "bumper/workers"
require "bumper/dependency"
require "bumper/dependency_file_updaters/ruby_dependency_file_updater"

module Workers
  class DependencyFileUpdater
    include Shoryuken::Worker

    shoryuken_options(
      queue: "bump-dependencies_to_update",
      body_parser: :json,
      auto_delete: true
    )

    def perform(_sqs_message, body)
      file_updater_class = file_updater_for(body["repo"]["language"])
      updated_dependency = Dependency.new(
        name: body["updated_dependency"]["name"],
        version: body["updated_dependency"]["version"]
      )

      dependency_files = body["dependency_files"].map do |file|
        DependencyFile.new(name: file["name"], content: file["content"])
      end

      file_updater = file_updater_class.new(
        dependency_files: dependency_files,
        dependency: updated_dependency
      )
      open_pull_request_for(
        body["repo"],
        body["updated_dependency"],
        file_updater.updated_dependency_files
      )
    end

    private

    def open_pull_request_for(repo, updated_dependency, updated_files)
      updated_dependency_files = updated_files.map! do |file|
        { "name" => file.name, "content" => file.content }
      end

      Workers::PullRequestCreator.perform_async(
        "repo" => repo,
        "updated_dependency" => updated_dependency,
        "updated_dependency_files" => updated_dependency_files
      )
    end

    def file_updater_for(language)
      case language
      when "ruby" then DependencyFileUpdaters::RubyDependencyFileUpdater
      else raise "Invalid language #{language}"
      end
    end
  end
end
