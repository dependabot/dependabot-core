# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/poetry_plugin_installer"
require "dependabot/python/poetry_project"
require "dependabot/python/subprocess_error_context"

module Dependabot
  module Python
    # Re-locks the named packages through the native helper's
    # `relock_poetry_project` function. It does what
    # `poetry update <names> --lock` does, without a Poetry subprocess per call.
    #
    # Callers write the prepared `pyproject.toml`, `poetry.lock` and
    # `.python-version` into the current directory and set credentials as
    # environment variables first, exactly as for the shell command. Running
    # under `pyenv exec` from that directory means the helper uses the
    # project's Python, like the shell command does.
    #
    # Only used when the `enable_native_poetry_helper` experiment is on.
    class PoetryRelocker
      extend T::Sig

      # Poetry couldn't find versions that satisfy the constraints. Running
      # the shell command would fail the same way, so this isn't retried.
      RESOLUTION_ERROR_CLASSES = %w(SolverProblemError).freeze

      class Result < T::ImmutableStruct
        const :lockfile, String
        # Every locked version of each requested package, keyed by normalised
        # name. More than one when the package is locked per marker.
        const :versions, T::Hash[String, T::Array[String]]
      end

      # Returns nil, so the caller runs the shell command, when the experiment
      # is off, when the project needs Poetry plugins (the helper doesn't load
      # them), or when the helper fails for a reason other than resolution.
      # Resolution failures are raised as `HelperSubprocessFailed` with
      # Poetry's message, so callers' existing error handling applies.
      sig do
        params(
          package_names: T::Array[String],
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential]
        ).returns(T.nilable(Result))
      end
      def self.relock_if_enabled(package_names:, dependency_files:, credentials:)
        return unless PoetryProject.enabled?
        return if PoetryPluginInstaller.from_dependency_files(dependency_files).plugins_required?

        relock(package_names)
      rescue SharedHelpers::HelperSubprocessFailed => e
        if resolution_failure?(e)
          SubprocessErrorContext.attach(
            e, command: "pyenv exec poetry update", dependency_files: dependency_files, credentials: credentials
          )
          raise
        end

        Dependabot.logger.warn("Native Poetry re-lock failed, using `poetry update`: #{e.message}")
        nil
      end

      sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
      def self.resolution_failure?(error)
        RESOLUTION_ERROR_CLASSES.include?(error.error_class)
      end

      sig { params(package_names: T::Array[String]).returns(Result) }
      def self.relock(package_names)
        result = SharedHelpers.run_helper_subprocess(
          command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
          function: "relock_poetry_project",
          args: [Dir.pwd, package_names]
        )
        parse_result(result)
      end

      sig { params(result: T.nilable(Object)).returns(Result) }
      def self.parse_result(result)
        hash = PoetryProject::Values.object_hash(result, "relock_poetry_project result")
        versions = PoetryProject::Values.object_hash(hash["versions"], "relock_poetry_project versions")
        Result.new(
          lockfile: PoetryProject::Values.string(hash["lockfile"], "relock_poetry_project lockfile"),
          versions: versions.transform_values do |value|
            PoetryProject::Values.string_array(value, "relock_poetry_project version list")
          end
        )
      end
      private_class_method :parse_result
    end
  end
end
