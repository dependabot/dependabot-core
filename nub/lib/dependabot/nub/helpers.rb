# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Nub
    module Helpers
      extend T::Sig

      # NUB Version Constants
      NUB_V1 = 1
      NUB_DEFAULT_VERSION = NUB_V1

      sig { params(_nub_lock: T.nilable(DependencyFile)).returns(Integer) }
      def self.nub_version_numeric(_nub_lock)
        NUB_DEFAULT_VERSION
      end

      sig { returns(T.nilable(String)) }
      def self.node_version
        version = run_node_command("-v", fingerprint: "-v").strip

        # Validate the output format (e.g., "v20.18.1" or "20.18.1")
        if version.match?(/^v?\d+(\.\d+){2}$/)
          version.strip.delete_prefix("v") # Remove the "v" prefix if present
        end
      rescue StandardError => e
        Dependabot.logger.error("Error retrieving Node.js version: #{e.message}")
        nil
      end

      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_node_command(command, fingerprint: nil)
        full_command = "node #{command}"

        Dependabot.logger.info("Running node command: #{full_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "node #{fingerprint || command}"
        )

        Dependabot.logger.info("Command executed successfully: #{full_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running node command: #{full_command}, Error: #{e.message}")
        raise
      end

      sig { returns(T.nilable(String)) }
      def self.nub_version
        version = run_nub_command("--version", fingerprint: "--version").strip
        if version.include?("+")
          version.split("+").first # Remove build info, if present
        end
      rescue StandardError => e
        Dependabot.logger.error("Error retrieving Nub version: #{e.message}")
        nil
      end

      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_nub_command(command, fingerprint: nil)
        full_command = "nub #{command}"

        Dependabot.logger.info("Running nub command: #{full_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "nub #{fingerprint || command}"
        )

        Dependabot.logger.info("Command executed successfully: #{full_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running nub command: #{full_command}, Error: #{e.message}")
        raise
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).returns(T::Array[Dependency]) }
      def self.dependencies_with_all_versions_metadata(dependency_set)
        dependency_set.dependencies.map do |dependency|
          dependency.metadata[:all_versions] = dependency_set.all_versions_for_name(dependency.name)
          dependency
        end
      end
    end
  end
end
