require "shoryuken"
require "bumper/workers"
require "bumper/dependency"
require "bumper/dependency_file_updaters/ruby_dependency_file_updater"

class Workers::DependencyFileUpdater
  include Shoryuken::Worker

  shoryuken_options(
    queue: "bump-dependencies_to_update",
    body_parser: :json,
    auto_delete: true,
  )

  def perform(sqs_message, body)
    file_updater_class = file_updater_for(body["repo"]["language"])
    updated_dependency = Dependency.new(
      name: body["updated_dependency"]["name"],
      version: body["updated_dependency"]["version"],
    )

    dependency_files = body["dependency_files"].map do |file|
      DependencyFile.new(name: file["name"], content: file["content"])
    end

    file_updater = file_updater_class.new(
      dependency_files: dependency_files,
      dependency: updated_dependency,
    )
    do_something_with(file_updater.updated_dependency_files)
  end

  private

  def do_something_with(updated_dependency_files)
    # TODO ....
  end

  def file_updater_for(language)
    case language
    when "ruby" then DependencyFileUpdaters::RubyDependencyFileUpdater
    else raise "Invalid language #{language}"
    end
  end
end
