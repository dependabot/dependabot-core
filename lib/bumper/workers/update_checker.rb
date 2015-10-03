require "shoryuken"
require "bumper/workers"
require "bumper/dependency"
require "bumper/update_checkers/ruby_update_checker"

module Workers
  class UpdateChecker
    include Shoryuken::Worker

    shoryuken_options(
      queue: "bump-dependencies_to_check",
      body_parser: :json,
      auto_delete: true
    )

    def perform(_sqs_message, body)
      dependency = Dependency.new(
        name: body["dependency"]["name"],
        version: body["dependency"]["version"]
      )

      update_checker_class = update_checker_for(body["repo"]["language"])
      update_checker = update_checker_class.new(dependency)

      return unless update_checker.needs_update?

      updated_dependency = Dependency.new(
        name: dependency.name,
        version: update_checker.latest_version
      )
      update_dependency(
        body["repo"],
        body["dependency_files"],
        updated_dependency
      )
    rescue => error
      Raven.capture_exception(error)
      raise
    end

    private

    def update_dependency(repo, dependency_files, updated_dependency)
      Workers::DependencyFileUpdater.perform_async(
        "repo" => repo,
        "dependency_files" => dependency_files,
        "updated_dependency" => {
          "name" => updated_dependency.name,
          "version" => updated_dependency.version
        }
      )
    end

    def update_checker_for(language)
      case language
      when "ruby" then UpdateCheckers::RubyUpdateChecker
      else raise "Invalid language #{language}"
      end
    end
  end
end
