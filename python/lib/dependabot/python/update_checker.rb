# typed: true
# frozen_string_literal: true

require "excon"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/python/name_normaliser"
require "dependabot/python/requirement_parser"
require "dependabot/python/requirement"
require "dependabot/registry_client"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Python
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/poetry_version_resolver"
      require_relative "update_checker/pipenv_version_resolver"
      require_relative "update_checker/pip_compile_version_resolver"
      require_relative "update_checker/pip_version_resolver"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/latest_version_finder"

      MAIN_PYPI_INDEXES = %w(
        https://pypi.python.org/simple/
        https://pypi.org/simple/
      ).freeze
      VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

      def latest_version
        @latest_version ||= fetch_latest_version
      end

      def latest_resolvable_version
        @latest_resolvable_version ||=
          if resolver_type == :requirements
            resolver.latest_resolvable_version
          elsif resolver_type == :pip_compile && resolver.resolvable?(version: latest_version)
            latest_version
          else
            resolver.latest_resolvable_version(
              requirement: unlocked_requirement_string
            )
          end
      end

      def latest_resolvable_version_with_no_unlock
        @latest_resolvable_version_with_no_unlock ||=
          if resolver_type == :requirements
            resolver.latest_resolvable_version_with_no_unlock
          else
            resolver.latest_resolvable_version(
              requirement: current_requirement_string
            )
          end
      end

      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        return @lowest_resolvable_security_fix_version if defined?(@lowest_resolvable_security_fix_version)

        @lowest_resolvable_security_fix_version =
          fetch_lowest_resolvable_security_fix_version
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: requirements,
          latest_resolvable_version: preferred_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy,
          has_lockfile: !(pipfile_lock || poetry_lock).nil?
        ).updated_requirements
      end

      def requirements_unlocked_or_can_be?
        !requirements_update_strategy.lockfile_only?
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy if @requirements_update_strategy

        # Otherwise, check if this is a library or not
        library? ? RequirementsUpdateStrategy::WidenRanges : RequirementsUpdateStrategy::BumpVersions
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Python (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def fetch_lowest_resolvable_security_fix_version
        fix_version = lowest_security_fix_version
        return latest_resolvable_version if fix_version.nil?

        return resolver.lowest_resolvable_security_fix_version if resolver_type == :requirements

        resolver.resolvable?(version: fix_version) ? fix_version : nil
      end

      def resolver
        if Dependabot::Experiments.enabled?(:enable_file_parser_python_local)
          Dependabot.logger.info("Python package resolver : #{resolver_type}")
        end

        case resolver_type
        when :pip_compile then pip_compile_version_resolver
        when :pipenv then pipenv_version_resolver
        when :poetry then poetry_version_resolver
        when :requirements then pip_version_resolver
        else raise "Unexpected resolver type #{resolver_type}"
        end
      end

      def resolver_type
        reqs = requirements

        # If there are no requirements then this is a sub-dependency. It
        # must come from one of Pipenv, Poetry or pip-tools, and can't come
        # from the first two unless they have a lockfile.
        return subdependency_resolver if reqs.none?

        # Otherwise, this is a top-level dependency, and we can figure out
        # which resolver to use based on the filename of its requirements
        return :pipenv if updating_pipfile?
        return pyproject_resolver if updating_pyproject?
        return :pip_compile if updating_in_file?

        if dependency.version && !exact_requirement?(reqs)
          subdependency_resolver
        else
          :requirements
        end
      end

      def subdependency_resolver
        return :pipenv if pipfile_lock
        return :poetry if poetry_lock
        return :pip_compile if pip_compile_files.any?

        raise "Claimed to be a sub-dependency, but no lockfile exists!"
      end

      def pyproject_resolver
        return :poetry if poetry_based?

        :requirements
      end

      def exact_requirement?(reqs)
        reqs = reqs.map { |r| r.fetch(:requirement) }
        reqs = reqs.compact
        reqs = reqs.flat_map { |r| r.split(",").map(&:strip) }
        reqs.any? { |r| Python::Requirement.new(r).exact? }
      end

      def pipenv_version_resolver
        @pipenv_version_resolver ||= PipenvVersionResolver.new(**resolver_args)
      end

      def pip_compile_version_resolver
        @pip_compile_version_resolver ||=
          PipCompileVersionResolver.new(**resolver_args)
      end

      def poetry_version_resolver
        @poetry_version_resolver ||= PoetryVersionResolver.new(**resolver_args)
      end

      def pip_version_resolver
        @pip_version_resolver ||= PipVersionResolver.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          update_cooldown: @update_cooldown,
          raise_on_ignored: @raise_on_ignored,
          security_advisories: security_advisories
        )
      end

      def resolver_args
        {
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          repo_contents_path: repo_contents_path
        }
      end

      def current_requirement_string
        reqs = requirements
        return if reqs.none?

        requirement = reqs.find do |r|
          file = r[:file]

          file == "Pipfile" || file == "pyproject.toml" || file.end_with?(".in") || file.end_with?(".txt")
        end

        requirement&.fetch(:requirement)
      end

      def unlocked_requirement_string
        lower_bound_req = updated_version_req_lower_bound

        # Add the latest_version as an upper bound. This means
        # ignore conditions are considered when checking for the latest
        # resolvable version.
        #
        # NOTE: This isn't perfect. If v2.x is ignored and v3 is out but
        # unresolvable then the `latest_version` will be v3, and
        # we won't be ignoring v2.x releases like we should be.
        return lower_bound_req if latest_version.nil?
        return lower_bound_req unless Python::Version.correct?(latest_version)

        lower_bound_req + ",<=#{latest_version}"
      end

      def updated_version_req_lower_bound
        return ">=#{dependency.version}" if dependency.version

        version_for_requirement =
          requirements.filter_map { |r| r[:requirement] }
                      .reject { |req_string| req_string.start_with?("<") }
                      .select { |req_string| req_string.match?(VERSION_REGEX) }
                      .map { |req_string| req_string.match(VERSION_REGEX).to_s }
                      .select { |version| Python::Version.correct?(version) }
                      .max_by { |version| Python::Version.new(version) }

        ">=#{version_for_requirement || 0}"
      end

      def fetch_latest_version
        latest_version_finder.latest_version
      end

      def latest_version_finder
        @latest_version_finder ||= LatestVersionFinder.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: @raise_on_ignored,
          cooldown_options: @update_cooldown,
          security_advisories: security_advisories
        )
      end

      def poetry_based?
        updating_pyproject? && !poetry_details.nil?
      end

      def library?
        return false unless updating_pyproject?

        return false if library_details["name"].nil?

        # Hit PyPi and check whether there are details for a library with a
        # matching name and description
        index_response = Dependabot::RegistryClient.get(
          url: "https://pypi.org/pypi/#{normalised_name(library_details['name'])}/json/"
        )

        return false unless index_response.status == 200

        pypi_info = JSON.parse(index_response.body)["info"] || {}
        pypi_info["summary"] == library_details["description"]
      rescue Excon::Error::Timeout, Excon::Error::Socket
        false
      rescue URI::InvalidURIError
        false
      end

      def updating_pipfile?
        requirement_files.any?("Pipfile")
      end

      def updating_pyproject?
        requirement_files.any?("pyproject.toml")
      end

      def updating_in_file?
        requirement_files.any? { |f| f.end_with?(".in") }
      end

      def updating_requirements_file?
        requirement_files.any? { |f| f =~ /\.txt$|\.in$/ }
      end

      def requirement_files
        requirements.map { |r| r.fetch(:file) }
      end

      def requirements
        dependency.requirements
      end

      def normalised_name(name)
        NameNormaliser.normalise(name)
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

      def poetry_lock
        dependency_files.find { |f| f.name == "poetry.lock" }
      end

      def library_details
        @library_details ||= poetry_details || standard_details || build_system_details
      end

      def poetry_details
        @poetry_details ||= toml_content.dig("tool", "poetry")
      end

      def standard_details
        @standard_details ||= toml_content["project"]
      end

      def build_system_details
        @build_system_details ||= toml_content["build-system"]
      end

      def toml_content
        @toml_content ||= TomlRB.parse(pyproject.content)
      end

      def pip_compile_files
        dependency_files.select { |f| f.name.end_with?(".in") }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("pip", Dependabot::Python::UpdateChecker)
