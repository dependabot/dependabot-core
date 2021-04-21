# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/pipfile_file_updater"
      require_relative "file_updater/pip_compile_file_updater"
      require_relative "file_updater/poetry_file_updater"
      require_relative "file_updater/requirement_file_updater"

      def self.updated_files_regex
        [
          /^Pipfile$/,
          /^Pipfile\.lock$/,
          /.*\.txt$/,
          /.*\.in$/,
          /^setup\.py$/,
          /^setup\.cfg$/,
          /^pyproject\.toml$/,
          /^pyproject\.lock$/
        ]
      end

      def updated_dependency_files
        updated_files =
          case resolver_type
          when :pipfile then updated_pipfile_based_files
          when :poetry then updated_poetry_based_files
          when :pip_compile then updated_pip_compile_based_files
          when :requirements then updated_requirement_based_files
          else raise "Unexpected resolver type: #{resolver_type}"
          end

        if updated_files.none? ||
           updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
          raise "No files have changed!"
        end

        updated_files
      end

      private

      # rubocop:disable Metrics/PerceivedComplexity
      def resolver_type
        reqs = dependencies.flat_map(&:requirements)
        changed_reqs = reqs.zip(dependencies.flat_map(&:previous_requirements)).
                       reject { |(new_req, old_req)| new_req == old_req }.
                       map(&:first)
        changed_req_files = changed_reqs.map { |r| r.fetch(:file) }

        # If there are no requirements then this is a sub-dependency. It
        # must come from one of Pipenv, Poetry or pip-tools, and can't come
        # from the first two unless they have a lockfile.
        return subdependency_resolver if changed_reqs.none?

        # Otherwise, this is a top-level dependency, and we can figure out
        # which resolver to use based on the filename of its requirements
        return :pipfile if changed_req_files.any? { |f| f == "Pipfile" }
        return :poetry if changed_req_files.any? { |f| f == "pyproject.toml" }
        return :pip_compile if changed_req_files.any? { |f| f.end_with?(".in") }

        :requirements
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def subdependency_resolver
        return :pipfile if pipfile_lock
        return :poetry if poetry_lock || pyproject_lock
        return :pip_compile if pip_compile_files.any?

        raise "Claimed to be a sub-dependency, but no lockfile exists!"
      end

      def updated_pipfile_based_files
        PipfileFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_dependency_files
      end

      def updated_poetry_based_files
        PoetryFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_dependency_files
      end

      def updated_pip_compile_based_files
        PipCompileFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_dependency_files
      end

      def updated_requirement_based_files
        RequirementFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_dependency_files
      end

      def check_required_files
        filenames = dependency_files.map(&:name)
        return if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return if pipfile
        return if pyproject
        return if get_original_file("setup.py")
        return if get_original_file("setup.cfg")

        raise "Missing required files!"
      end

      def pipfile
        @pipfile ||= get_original_file("Pipfile")
      end

      def pipfile_lock
        @pipfile_lock ||= get_original_file("Pipfile.lock")
      end

      def pyproject
        @pyproject ||= get_original_file("pyproject.toml")
      end

      def pyproject_lock
        @pyproject_lock ||= get_original_file("pyproject.lock")
      end

      def poetry_lock
        @poetry_lock ||= get_original_file("poetry.lock")
      end

      def pip_compile_files
        @pip_compile_files ||=
          dependency_files.select { |f| f.name.end_with?(".in") }
      end
    end
  end
end

Dependabot::FileUpdaters.register("pip", Dependabot::Python::FileUpdater)
