# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/package_manager"
require "dependabot/npm_and_yarn/file_updater/npmrc_builder"

module Dependabot
  module NpmAndYarn
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      class LockfileGenerator
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            package_manager: String,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, package_manager:, credentials:)
          @dependency_files = dependency_files
          @package_manager = package_manager
          @credentials = credentials
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def generate
          SharedHelpers.in_a_temporary_directory do
            write_temporary_files
            run_lockfile_generation
            read_generated_lockfile
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_generation_error(e)
          nil
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(String) }
        attr_reader :package_manager

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def write_temporary_files
          write_package_files
          write_npmrc
          write_yarnrc if yarn?
        end

        sig { void }
        def write_package_files
          dependency_files.each do |file|
            next unless file.name.end_with?(
              "package.json", ".npmrc", ".yarnrc", ".yarnrc.yml", "pnpm-workspace.yaml"
            )

            path = file.name
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, file.content)
          end
        end

        sig { void }
        def write_npmrc
          # Skip if .npmrc already exists in dependency files (already written above)
          return if dependency_files.any? { |f| f.name.end_with?(".npmrc") }

          # Use NpmrcBuilder to generate npmrc content from credentials
          npmrc_content = FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content

          return if npmrc_content.empty?

          File.write(".npmrc", npmrc_content)
        end

        sig { void }
        def write_yarnrc
          return unless yarn_berry?

          # For Yarn Berry, set up the environment properly
          Helpers.setup_yarn_berry
        end

        sig { void }
        def run_lockfile_generation
          Dependabot.logger.info("Generating lockfile using #{package_manager}")

          case package_manager
          when NpmPackageManager::NAME
            run_npm_lockfile_generation
          when YarnPackageManager::NAME
            run_yarn_lockfile_generation
          when PNPMPackageManager::NAME
            run_pnpm_lockfile_generation
          else
            raise "Unknown package manager: #{package_manager}"
          end
        end

        sig { void }
        def run_npm_lockfile_generation
          # Set dependency files and credentials for automatic env variable injection
          Helpers.dependency_files = dependency_files
          Helpers.credentials = credentials

          # Use --package-lock-only to generate lockfile without installing node_modules
          # Use --ignore-scripts to prevent running any scripts
          # Use --force to ignore platform checks
          command = "install --package-lock-only --ignore-scripts --force"
          Helpers.run_npm_command(command, fingerprint: command)
        end

        sig { void }
        def run_yarn_lockfile_generation
          if yarn_berry?
            # Yarn Berry (2+) uses different commands
            Helpers.run_yarn_command("install --mode update-lockfile")
          else
            # Yarn Classic (1.x)
            SharedHelpers.run_shell_command(
              "yarn install --ignore-scripts --frozen-lockfile=false",
              fingerprint: "yarn install --ignore-scripts --frozen-lockfile=false"
            )
          end
        end

        sig { void }
        def run_pnpm_lockfile_generation
          # pnpm uses --lockfile-only to generate lockfile without installing
          command = "install --lockfile-only --ignore-scripts"
          Helpers.run_pnpm_command(command, fingerprint: command)
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def read_generated_lockfile
          lockfile_name = expected_lockfile_name

          unless File.exist?(lockfile_name)
            Dependabot.logger.warn("Lockfile #{lockfile_name} was not generated")
            return nil
          end

          content = File.read(lockfile_name)

          Dependabot::DependencyFile.new(
            name: lockfile_name,
            content: content,
            directory: "/"
          )
        end

        sig { returns(String) }
        def expected_lockfile_name
          case package_manager
          when NpmPackageManager::NAME
            NpmPackageManager::LOCKFILE_NAME
          when YarnPackageManager::NAME
            YarnPackageManager::LOCKFILE_NAME
          when PNPMPackageManager::NAME
            PNPMPackageManager::LOCKFILE_NAME
          else
            "package-lock.json"
          end
        end

        sig { returns(T::Boolean) }
        def yarn?
          package_manager == YarnPackageManager::NAME
        end

        sig { returns(T::Boolean) }
        def yarn_berry?
          return false unless yarn?

          # Check for .yarnrc.yml which indicates Yarn Berry
          dependency_files.any? { |f| f.name.end_with?(".yarnrc.yml") }
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
        def handle_generation_error(error)
          Dependabot.logger.error(
            "Failed to generate lockfile with #{package_manager}: #{error.message}"
          )

          # Log more details for debugging
          if error.message.include?("ERESOLVE")
            Dependabot.logger.error(
              "Dependency resolution failed. This may be due to conflicting peer dependencies."
            )
          elsif error.message.include?("ENOTFOUND") || error.message.include?("ETIMEDOUT")
            Dependabot.logger.error(
              "Network error while generating lockfile. Registry may be unreachable."
            )
          elsif error.message.include?("401") || error.message.include?("403")
            Dependabot.logger.error(
              "Authentication error. Check that credentials are configured correctly."
            )
          end
        end
      end
    end
  end
end
