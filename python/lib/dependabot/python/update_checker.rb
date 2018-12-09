# frozen_string_literal: true

require "excon"
require "toml-rb"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/python/requirement"
require "dependabot/python/requirement_parser"

module Dependabot
  module Python
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/poetry_version_resolver"
      require_relative "update_checker/pipfile_version_resolver"
      require_relative "update_checker/pip_compile_version_resolver"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/latest_version_finder"

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
          update_strategy: requirements_update_strategy,
          has_lockfile: !(pipfile_lock || poetry_lock || pyproject_lock).nil?
        ).updated_requirements
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        if @requirements_update_strategy
          return @requirements_update_strategy.to_sym
        end

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

      # rubocop:disable Metrics/PerceivedComplexity
      def resolver_type
        reqs = dependency.requirements
        req_files = reqs.map { |r| r.fetch(:file) }

        # If there are no requirements then this is a sub-dependency. It
        # must come from one of Pipenv, Poetry or pip-tools, and can't come
        # from the first two unless they have a lockfile.
        return subdependency_resolver if reqs.none?

        # Otherwise, this is a top-level dependency, and we can figure out
        # which resolver to use based on the filename of its requirements
        return :pipfile if req_files.any? { |f| f == "Pipfile" }
        return :poetry if req_files.any? { |f| f == "pyproject.toml" }
        return :pip_compile if req_files.any? { |f| f.end_with?(".in") }

        if dependency.version && !exact_requirement?(reqs)
          subdependency_resolver
        else
          :requirements
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def subdependency_resolver
        return :pipfile if pipfile_lock
        return :poetry if poetry_lock || pyproject_lock
        return :pip_compile if pip_compile_files.any?

        raise "Claimed to be a sub-dependency, but no lockfile exists!"
      end

      def exact_requirement?(reqs)
        reqs = reqs.map { |r| r.fetch(:requirement) }
        reqs = reqs.compact
        reqs = reqs.flat_map { |r| r.split(",").map(&:strip) }
        reqs.any? { |r| Python::Requirement.new(r).exact? }
      end

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
        name.downcase.gsub(/[-_.]+/, "-")
      end

      def pipfile
        dependency_files.find { |f| f.name == "Pipfile" }
      end

      def pipfile_lock
        dependency_files.find { |f| f.name == "Pipfile.lock" }
      end

      def pyproject
        dependency_files.find { |f| f.name == "pyproject.toml" }
      end

      def pyproject_lock
        dependency_files.find { |f| f.name == "pyproject.lock" }
      end

      def poetry_lock
        dependency_files.find { |f| f.name == "poetry.lock" }
      end

      def pip_compile_files
        dependency_files.select { |f| f.name.end_with?(".in") }
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("pip", Dependabot::Python::UpdateChecker)
