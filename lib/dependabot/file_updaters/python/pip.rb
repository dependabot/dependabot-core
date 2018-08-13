# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip < Dependabot::FileUpdaters::Base
        require_relative "pip/pipfile_file_updater"
        require_relative "pip/pip_compile_file_updater"
        require_relative "pip/poetry_file_updater"
        require_relative "pip/requirement_file_updater"

        def self.updated_files_regex
          [
            /^Pipfile$/,
            /^Pipfile\.lock$/,
            /.*\.txt$/,
            /.*\.in$/,
            /^setup\.py$/
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

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def resolver_type
          reqs = dependencies.flat_map(&:requirements)

          if (pipfile && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file) == "Pipfile" }
            return :pipfile
          end

          if (pyproject && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file) == "pyproject.toml" }
            return :poetry
          end

          if (pip_compile_files.any? && reqs.none?) ||
             reqs.any? { |r| r.fetch(:file).end_with?(".in") }
            return :pip_compile
          end

          :requirements
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

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
          return if filenames.any? { |name| name.end_with?(".txt") }
          return if filenames.any? { |name| name.end_with?(".in") }
          return if (%w(Pipfile Pipfile.lock) - filenames).empty?
          return if get_original_file("pyproject.toml")
          return if get_original_file("setup.py")
          raise "No requirements.txt or setup.py!"
        end

        def pipfile
          @pipfile ||= get_original_file("Pipfile")
        end

        def pyproject
          @pyproject ||= get_original_file("pyproject.toml")
        end

        def pip_compile_files
          @pip_compile_files ||=
            dependency_files.select { |f| f.name.end_with?(".in") }
        end
      end
    end
  end
end
