# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/shared_helpers"

module Dependabot
  module Uv
    class UvVersionManager
      extend T::Sig

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
      def initialize(dependency_files:)
        @dependency_files = dependency_files
      end

      sig { void }
      def ensure_correct_version
        required_version = required_uv_version
        if required_version
          current_version = current_uv_version
          if current_version && current_version != required_version
            Dependabot.logger.info(
              "Current uv version (#{current_version}) does not match required version (#{required_version}). " \
              "Updating uv..."
            )
            update_uv_to_version(required_version)
          elsif current_version
            Dependabot.logger.info("Using uv version #{current_version}")
          else
            Dependabot.logger.info("Using pre-installed uv package")
          end
        else
          Dependabot.logger.info("Using pre-installed uv package")
        end
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T.nilable(String)) }
      def required_uv_version
        pyproject_file = dependency_files.find { |f| f.name == "pyproject.toml" }
        return nil unless pyproject_file

        parsed_pyproject = TomlRB.parse(pyproject_file.content)
        required_version = parsed_pyproject.dig("tool", "uv", "required-version")

        if required_version
          # Remove any leading/trailing whitespace and version prefix (e.g., "==")
          required_version = required_version.strip.sub(/^==\s*/, "")
          Dependabot.logger.info("Found required uv version in pyproject.toml: #{required_version}")
        end

        required_version
      rescue TomlRB::ParseError => e
        Dependabot.logger.warn("Failed to parse pyproject.toml for required uv version: #{e.message}")
        nil
      end

      sig { returns(T.nilable(String)) }
      def current_uv_version
        version_output = SharedHelpers.run_shell_command("pyenv exec uv --version").strip
        # Parse version from output like "uv 0.9.11" or "uv 0.9.11 (abc123)"
        # Support semantic versions with optional pre-release/build metadata
        version_match = version_output.match(/uv\s+(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)/)
        version_match[1] if version_match
      rescue StandardError => e
        Dependabot.logger.warn("Failed to get current uv version: #{e.message}")
        nil
      end

      sig { params(version: String).void }
      def update_uv_to_version(version)
        Dependabot.logger.info("Updating uv to version #{version}")

        # Use pip to install the required uv version since the bundled uv
        # in Docker was not installed via standalone installer
        SharedHelpers.run_shell_command(
          "pyenv exec pip install --force-reinstall --no-deps uv==#{version}"
        )

        # Verify the installation
        installed_version = current_uv_version
        unless installed_version == version
          raise "Failed to update uv: expected version #{version}, but got #{installed_version}"
        end

        Dependabot.logger.info("Successfully updated uv to version #{version}")
      rescue StandardError => e
        Dependabot.logger.error("Failed to update uv to version #{version}: #{e.message}")
        raise
      end
    end
  end
end
