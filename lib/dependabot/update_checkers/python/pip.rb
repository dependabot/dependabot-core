# frozen_string_literal: true

require "excon"
require "toml-rb"

require "python_requirement_parser"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip < Dependabot::UpdateCheckers::Base
        require_relative "pip/poetry_version_resolver"
        require_relative "pip/pipfile_version_resolver"
        require_relative "pip/pip_compile_version_resolver"
        require_relative "pip/requirements_updater"
        require_relative "pip/latest_version_finder"

        MAIN_PYPI_INDEXES = %w(
          https://pypi.python.org/simple/
          https://pypi.org/simple/
        ).freeze

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          @latest_resolvable_version ||=
            case resolver_type
            when :pipfile
              PipfileVersionResolver.new(
                resolver_args.merge(unlock_requirement: true)
              ).latest_resolvable_version
            when :poetry
              PoetryVersionResolver.new(
                resolver_args.merge(unlock_requirement: true)
              ).latest_resolvable_version
            when :pip_compile
              PipCompileVersionResolver.new(
                resolver_args.merge(unlock_requirement: true)
              ).latest_resolvable_version
            when :requirements
              # pip doesn't (yet) do any dependency resolution, so if we don't
              # have a Pipfile or a pip-compile file, we just return the latest
              # version.
              latest_version
            else raise "Unexpected resolver type #{resolver_type}"
            end
        end

        def latest_resolvable_version_with_no_unlock
          @latest_resolvable_version_with_no_unlock ||=
            case resolver_type
            when :pipfile
              PipfileVersionResolver.new(
                resolver_args.merge(unlock_requirement: false)
              ).latest_resolvable_version
            when :poetry
              PoetryVersionResolver.new(
                resolver_args.merge(unlock_requirement: false)
              ).latest_resolvable_version
            when :pip_compile
              PipCompileVersionResolver.new(
                resolver_args.merge(unlock_requirement: false)
              ).latest_resolvable_version
            when :requirements
              latest_pip_version_with_no_unlock
            else raise "Unexpected resolver type #{resolver_type}"
            end
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s,
            update_strategy: requirements_update_strategy
          ).updated_requirements
        end

        def requirements_update_strategy
          # If passed in as an option (in the base class) honour that option
          return @requirements_update_strategy if @requirements_update_strategy

          # Otherwise, check if this is a poetry library or not
          poetry_library? ? :widen_ranges : :bump_versions
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for pip because they're not
          # relevant (pip doesn't have a resolver). This method always returns
          # false to ensure `updated_dependencies_after_full_unlock` is never
          # called.
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def resolver_type
          reqs = dependency.requirements

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

        def resolver_args
          {
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            latest_allowable_version: latest_version
          }
        end

        def fetch_latest_version
          latest_version_finder.latest_version
        end

        def latest_pip_version_with_no_unlock
          latest_version_finder.latest_version_with_no_unlock
        end

        def latest_version_finder
          @latest_version_finder ||= LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions
          )
        end

        def poetry_library?
          return false unless pyproject

          # Hit PyPi and check whether there are details for a library with a
          # matching name and description
          details = TomlRB.parse(pyproject.content).dig("tool", "poetry")
          return false unless details

          index_response = Excon.get(
            "https://pypi.org/pypi/#{normalised_name(details['name'])}/json",
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          return false unless index_response.status == 200

          pypi_info = JSON.parse(index_response.body)["info"] || {}
          pypi_info["summary"] == details["description"]
        rescue URI::InvalidURIError
          false
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name(name)
          name.downcase.tr("_", "-").tr(".", "-")
        end

        def pipfile
          dependency_files.find { |f| f.name == "Pipfile" }
        end

        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def pip_compile_files
          dependency_files.select { |f| f.name.end_with?(".in") }
        end
      end
    end
  end
end
