# typed: strict
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"
require "toml-rb"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/experiments"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    # Installs the Poetry version declared in a project's manifest, similar to
    # how corepack activates the project-pinned package manager for npm/yarn.
    #
    # Reads `[tool.poetry] requires-poetry` from `pyproject.toml`, extracts the
    # first concrete version referenced by the constraint, and runs
    # `pyenv exec poetry self update <version>` to switch the bundled Poetry to
    # that version.
    #
    # Gated by the `:enable_poetry_version_install` experiment so the behaviour
    # can be rolled out incrementally.
    class PoetryVersionInstaller
      extend T::Sig

      FEATURE_FLAG = :enable_poetry_version_install

      # Only allow strict numeric versions (e.g. 2, 2.1, 2.1.3) to prevent
      # command injection via the version segment.
      VALID_VERSION = /\A\d+(?:\.\d+){0,2}\z/

      # Capture the first concrete version referenced by a PEP 440 style
      # constraint such as `==2.1.3`, `>=2.0`, `~=2.1`, `>2.0`.
      VERSION_FROM_CONSTRAINT = /(?:==|>=|~=|>)\s*(\d+(?:\.\d+){0,2})/

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(PoetryVersionInstaller) }
      def self.from_dependency_files(dependency_files)
        pyproject_content = dependency_files.find { |f| f.name == "pyproject.toml" }&.content
        new(pyproject_content: pyproject_content)
      end

      sig { params(pyproject_content: T.nilable(String)).void }
      def initialize(pyproject_content:)
        @pyproject_content = T.let(pyproject_content, T.nilable(String))
        @version_installed = T.let(false, T::Boolean)
      end

      sig { void }
      def install_required_version
        return unless Dependabot::Experiments.enabled?(FEATURE_FLAG)
        return if @version_installed

        version = target_version
        return unless version

        install_version(version)

        @version_installed = true
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :pyproject_content

      sig { returns(T.nilable(String)) }
      def target_version
        return nil unless pyproject_content

        parsed = TomlRB.parse(pyproject_content)
        constraint = parsed.dig("tool", "poetry", "requires-poetry")
        return nil unless constraint.is_a?(String) && !constraint.strip.empty?

        match = constraint.match(VERSION_FROM_CONSTRAINT)
        return nil unless match

        version = match[1]
        return nil unless version && VALID_VERSION.match?(version)

        version
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        nil
      end

      sig { params(version: String).void }
      def install_version(version)
        Dependabot.logger.info("Installing Poetry version: #{version}")

        escaped = Shellwords.shellescape(version)
        SharedHelpers.run_shell_command(
          "pyenv exec poetry self update #{escaped}",
          fingerprint: "pyenv exec poetry self update <version>"
        )
      rescue SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn(
          "Failed to install Poetry version #{version}: #{e.message}"
        )
      end
    end
  end
end
