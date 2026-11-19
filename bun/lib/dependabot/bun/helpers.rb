# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Bun
    module Helpers
      extend T::Sig

      # BUN Version Constants
      BUN_V1 = 1
      BUN_DEFAULT_VERSION = BUN_V1

      sig { params(_bun_lock: T.nilable(DependencyFile)).returns(Integer) }
      def self.bun_version_numeric(_bun_lock)
        BUN_DEFAULT_VERSION
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
      def self.bun_version
        version = run_bun_command("--version", fingerprint: "--version").strip
        if version.include?("+")
          version.split("+").first # Remove build info, if present
        end
      rescue StandardError => e
        Dependabot.logger.error("Error retrieving Bun version: #{e.message}")
        nil
      end

      sig { params(command: T.any(String, T::Array[String]), fingerprint: T.nilable(String)).returns(String) }
      def self.run_bun_command(command, fingerprint: nil)
        full_command = command.is_a?(Array) ? ["bun", *command] : "bun #{command}"
        display_command = full_command.is_a?(Array) ? full_command.join(" ") : full_command
        fingerprint_command = command.is_a?(Array) ? command.join(" ") : command

        Dependabot.logger.info("Running bun command: #{display_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "bun #{fingerprint || fingerprint_command}"
        )

        Dependabot.logger.info("Command executed successfully: #{display_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running bun command: #{display_command}, Error: #{e.message}")
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
