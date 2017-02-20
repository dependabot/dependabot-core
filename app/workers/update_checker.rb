require "sidekiq"
require "./app/boot"
require "./app/dependency"
require "./app/dependency_file"
require "./app/repo"
require "./app/update_checkers/ruby"
require "./app/update_checkers/node"
require "./app/dependency_file_updaters/ruby"
require "./app/dependency_file_updaters/node"
require "./app/workers/pull_request_creator"

$stdout.sync = true

module Workers
  class UpdateChecker
    include Sidekiq::Worker

    sidekiq_options queue: "bump-dependencies_to_check", retry: false

    def perform(body)
      @repo = Repo.new(**body["repo"].symbolize_keys)
      @dependency = Dependency.new(**body["dependency"].symbolize_keys)
      @dependency_files = body["dependency_files"].map do |file|
        DependencyFile.new(**file.symbolize_keys)
      end

      updated_dependency, updated_dependency_files = update_dependency!

      return if updated_dependency.nil?

      Workers::PullRequestCreator.perform_async(
        "repo" => repo.to_h,
        "updated_dependency" => updated_dependency.to_h,
        "updated_dependency_files" => updated_dependency_files.map(&:to_h)
      )
    rescue DependencyFileUpdaters::VersionConflict
      nil
    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
    end

    private

    attr_reader :dependency, :dependency_files, :repo

    def update_dependency!
      checker = update_checker.new(
        dependency: dependency,
        dependency_files: dependency_files
      )

      return unless checker.needs_update?

      updated_dependency = checker.updated_dependency

      updated_dependency_files = file_updater.new(
        dependency: updated_dependency,
        dependency_files: dependency_files
      ).updated_dependency_files

      [updated_dependency, updated_dependency_files]
    end

    def update_checker
      case repo.language
      when "ruby" then UpdateCheckers::Ruby
      when "node" then UpdateCheckers::Node
      else raise "Invalid language #{language}"
      end
    end

    def file_updater
      case repo.language
      when "ruby" then DependencyFileUpdaters::Ruby
      when "node" then DependencyFileUpdaters::Node
      else raise "Invalid language #{language}"
      end
    end
  end
end
