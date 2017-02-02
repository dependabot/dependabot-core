require "sidekiq"
require "./app/boot"
require "./app/dependency"
require "./app/dependency_file_updaters/ruby"
require "./app/dependency_file_updaters/node"
require "./app/workers/pull_request_creator"

$stdout.sync = true

module Workers
  class DependencyFileUpdater
    include Sidekiq::Worker

    sidekiq_options queue: "bump-dependencies_to_update", retry: false

    def perform(body)
      updated_dependency = Dependency.new(
        name: body["updated_dependency"]["name"],
        version: body["updated_dependency"]["version"],
        previous_version: body["updated_dependency"]["previous_version"]
      )

      dependency_files = body["dependency_files"].map do |file|
        DependencyFile.new(name: file["name"], content: file["content"])
      end

      file_updater = file_updater_for(body["repo"]["language"]).new(
        dependency: updated_dependency,
        dependency_files: dependency_files
      )

      open_pull_request_for(body["repo"],
                            body["updated_dependency"],
                            file_updater.updated_dependency_files)
    rescue DependencyFileUpdaters::VersionConflict
      nil
    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
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
      when "ruby" then DependencyFileUpdaters::Ruby
      when "node" then DependencyFileUpdaters::Node
      else raise "Invalid language #{language}"
      end
    end
  end
end
