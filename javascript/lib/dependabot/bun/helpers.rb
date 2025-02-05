# typed: strong
# frozen_string_literal: true

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
      def self.bun_version
        run_bun_command("--version", fingerprint: "--version").strip
      rescue StandardError => e
        Dependabot.logger.error("Error retrieving Bun version: #{e.message}")
        nil
      end

      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_bun_command(command, fingerprint: nil)
        full_command = "bun #{command}"

        Dependabot.logger.info("Running bun command: #{full_command}")

        result = Dependabot::SharedHelpers.run_shell_command(
          full_command,
          fingerprint: "bun #{fingerprint || command}"
        )

        Dependabot.logger.info("Command executed successfully: #{full_command}")
        result
      rescue StandardError => e
        Dependabot.logger.error("Error running bun command: #{full_command}, Error: #{e.message}")
        raise
      end

      # Fetch the currently installed version of the package manager directly
      # from the system
      sig { params(name: String).returns(String) }
      def self.local_package_manager_version(name)
        Dependabot::SharedHelpers.run_shell_command(
          "#{name} -v",
          fingerprint: "#{name} -v"
        ).strip
      end

      # Run single command on package manager returning stdout/stderr
      sig do
        params(
          name: String,
          command: String,
          fingerprint: T.nilable(String)
        ).returns(String)
      end
      def self.package_manager_run_command(name, command, fingerprint: nil)
        return run_bun_command(command, fingerprint: fingerprint) if name == PackageManager::NAME

        # TODO: remove this method and just use the one in the PackageManager class
        "noop"
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).returns(T::Array[Dependency]) }
      def self.dependencies_with_all_versions_metadata(dependency_set)
        # TODO: Check if we still need this method
        dependency_set.dependencies.map do |dependency|
          dependency.metadata[:all_versions] = dependency_set.all_versions_for_name(dependency.name)
          dependency
        end
      end
    end
  end
end
