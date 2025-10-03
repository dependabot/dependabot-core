# typed: strict
# frozen_string_literal: true

require "excon"
require "toml-rb"
require "sorbet-runtime"

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
      extend T::Sig

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

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_version
        @latest_version ||= T.let(
          fetch_latest_version,
          T.nilable(Gem::Version)
        )
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_resolvable_version
        @latest_resolvable_version ||= T.let(
          if resolver_type == :requirements
            resolver.latest_resolvable_version
          elsif resolver_type == :pip_compile && resolver.resolvable?(version: latest_version)
            latest_version
          else
            resolver.latest_resolvable_version(
              requirement: unlocked_requirement_string
            )
          end,
          T.nilable(Gem::Version)
        )
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_resolvable_version_with_no_unlock
        @latest_resolvable_version_with_no_unlock ||= T.let(
          if resolver_type == :requirements
            resolver.latest_resolvable_version_with_no_unlock
          else
            resolver.latest_resolvable_version(
              requirement: current_requirement_string
            )
          end,
          T.nilable(Gem::Version)
        )
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        @lowest_resolvable_security_fix_version ||= T.let(
          fetch_lowest_resolvable_security_fix_version,
          T.nilable(Gem::Version)
        )
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: requirements,
          latest_resolvable_version: preferred_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy,
          has_lockfile: !(pipfile_lock || poetry_lock).nil?
        ).updated_requirements
      end

      sig { override.returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        !requirements_update_strategy.lockfile_only?
      end

      sig { override.returns(Dependabot::RequirementsUpdateStrategy) }
      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy if @requirements_update_strategy

        # Otherwise, check if this is a library or not
        library? ? RequirementsUpdateStrategy::WidenRanges : RequirementsUpdateStrategy::BumpVersions
      end

      sig { override.returns(T::Array[T::Hash[String, String]]) }
      def conflicting_dependencies
        return [] unless vulnerable?

        target_version = lowest_security_fix_version
        return [] unless target_version

        # Get the Python version requirement for the target version
        target_python_requirement = python_requirement_for_version(target_version.to_s)
        return [] unless target_python_requirement

        # Get the current Python version being used
        # We need to get the language version manager from the pip version resolver
        # since it's the component that determines Python version
        language_version_mgr = if resolver_type == :requirements
                                 pip_version_resolver.language_version_manager
                               else
                                 # For other resolver types, we don't have easy access to Python version
                                 # Return empty array for now
                                 return []
                               end

        current_python_version = language_version_mgr.python_version
        current_python = Dependabot::Python::Version.new(current_python_version)

        # Check if the target version's Python requirement is satisfied by current Python
        unless target_python_requirement.satisfied_by?(current_python)
          [{
            "explanation" => "#{dependency.name} #{target_version} requires Python " \
                             "#{target_python_requirement}, but the current environment uses Python #{current_python_version}"
          }]
        else
          []
        end
      rescue StandardError => e
        Dependabot.logger.warn("Error checking conflicting dependencies: #{e.message}")
        []
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Python (yet)
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_lowest_resolvable_security_fix_version
        fix_version = lowest_security_fix_version
        return latest_resolvable_version if fix_version.nil?

        return resolver.lowest_resolvable_security_fix_version if resolver_type == :requirements

        resolver.resolvable?(version: fix_version) ? fix_version : nil
      end

      sig { returns(T.untyped) }
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

      sig { returns(Symbol) }
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

      sig { returns(Symbol) }
      def subdependency_resolver
        return :pipenv if pipfile_lock
        return :poetry if poetry_lock
        return :pip_compile if pip_compile_files.any?

        raise "Claimed to be a sub-dependency, but no lockfile exists!"
      end

      sig { returns(Symbol) }
      def pyproject_resolver
        return :poetry if poetry_based?

        :requirements
      end

      sig { params(reqs: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
      def exact_requirement?(reqs)
        reqs = reqs.map { |r| r.fetch(:requirement) }
        reqs = reqs.compact
        reqs = reqs.flat_map { |r| r.split(",").map(&:strip) }
        reqs.any? { |r| Python::Requirement.new(r).exact? }
      end

      sig { returns(PipenvVersionResolver) }
      def pipenv_version_resolver
        @pipenv_version_resolver ||= T.let(
          PipenvVersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          ),
          T.nilable(PipenvVersionResolver)
        )
      end

      sig { returns(PipCompileVersionResolver) }
      def pip_compile_version_resolver
        @pip_compile_version_resolver ||= T.let(
          PipCompileVersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          ),
          T.nilable(PipCompileVersionResolver)
        )
      end

      sig { returns(PoetryVersionResolver) }
      def poetry_version_resolver
        @poetry_version_resolver ||= T.let(
          PoetryVersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          ),
          T.nilable(PoetryVersionResolver)
        )
      end

      sig { returns(PipVersionResolver) }
      def pip_version_resolver
        @pip_version_resolver ||= T.let(
          PipVersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            update_cooldown: @update_cooldown,
            raise_on_ignored: @raise_on_ignored,
            security_advisories: security_advisories
          ),
          T.nilable(PipVersionResolver)
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def resolver_args
        {
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          repo_contents_path: repo_contents_path
        }
      end

      sig { returns(T.nilable(String)) }
      def current_requirement_string
        reqs = requirements
        return if reqs.none?

        requirement = reqs.find do |r|
          file = r[:file]

          file == "Pipfile" || file == "pyproject.toml" || file.end_with?(".in") || file.end_with?(".txt")
        end

        requirement&.fetch(:requirement)
      end

      sig { returns(String) }
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

      sig { returns(String) }
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

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_version
        latest_version_finder.latest_version
      end

      sig { returns(LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            cooldown_options: @update_cooldown,
            security_advisories: security_advisories
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig { returns(T::Boolean) }
      def poetry_based?
        updating_pyproject? && !poetry_details.nil?
      end

      sig { returns(T::Boolean) }
      def library?
        return false unless updating_pyproject?
        return false unless library_details

        return false if T.must(library_details)["name"].nil?

        # Hit PyPi and check whether there are details for a library with a
        # matching name and description
        index_response = Dependabot::RegistryClient.get(
          url: "https://pypi.org/pypi/#{normalised_name(T.must(library_details)['name'])}/json/"
        )

        return false unless index_response.status == 200

        pypi_info = JSON.parse(index_response.body)["info"] || {}
        pypi_info["summary"] == T.must(library_details)["description"]
      rescue Excon::Error::Timeout, Excon::Error::Socket
        false
      rescue URI::InvalidURIError
        false
      end

      sig { returns(T::Boolean) }
      def updating_pipfile?
        requirement_files.any?("Pipfile")
      end

      sig { returns(T::Boolean) }
      def updating_pyproject?
        requirement_files.any?("pyproject.toml")
      end

      sig { returns(T::Boolean) }
      def updating_in_file?
        requirement_files.any? { |f| f.end_with?(".in") }
      end

      sig { returns(T::Boolean) }
      def updating_requirements_file?
        requirement_files.any? { |f| f =~ /\.txt$|\.in$/ }
      end

      sig { returns(T::Array[String]) }
      def requirement_files
        requirements.map { |r| r.fetch(:file) }
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def requirements
        dependency.requirements
      end

      sig { params(name: String).returns(String) }
      def normalised_name(name)
        NameNormaliser.normalise(name)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile
        dependency_files.find { |f| f.name == "Pipfile" }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile_lock
        dependency_files.find { |f| f.name == "Pipfile.lock" }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        dependency_files.find { |f| f.name == "pyproject.toml" }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def poetry_lock
        dependency_files.find { |f| f.name == "poetry.lock" }
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def library_details
        @library_details ||= T.let(
          poetry_details || standard_details || build_system_details,
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def poetry_details
        @poetry_details ||= T.let(
          toml_content.dig("tool", "poetry"),
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def standard_details
        @standard_details ||= T.let(
          toml_content["project"],
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def build_system_details
        @build_system_details ||= T.let(
          toml_content["build-system"],
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def toml_content
        @toml_content ||= T.let(
          TomlRB.parse(T.must(pyproject).content),
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pip_compile_files
        dependency_files.select { |f| f.name.end_with?(".in") }
      end

      sig { params(version: String).returns(T.nilable(Dependabot::Python::Requirement)) }
      def python_requirement_for_version(version)
        # Get package details for the dependency
        package_details = latest_version_finder.package_details
        return nil unless package_details

        # Find the release for the target version
        target_release = package_details.releases.find { |r| r.version.to_s == version }
        return nil unless target_release

        # Get the language requirement
        language_info = target_release.language
        return nil unless language_info

        language_info.requirement
      end
    end
  end
end

Dependabot::UpdateCheckers.register("pip", Dependabot::Python::UpdateChecker)
