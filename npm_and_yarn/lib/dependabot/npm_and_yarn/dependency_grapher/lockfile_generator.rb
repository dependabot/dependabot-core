# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/package_manager"
require "dependabot/npm_and_yarn/file_updater/npmrc_builder"
require "yaml"
require "dependabot/npm_and_yarn/registry_helper"

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
          # Use --package-lock-only to generate lockfile without installing node_modules
          # Use --ignore-scripts to prevent running any scripts
          # Use --force to ignore platform checks
          # Use --dry-run false because global .npmrc may have dry-run: true set
          command = "install --package-lock-only --ignore-scripts --force --dry-run false"
          env = build_registry_env_variables
          Helpers.run_npm_command(command, fingerprint: command, env: env)
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

        sig { returns(T::Hash[String, String]) }
        def build_registry_env_variables
          return {} unless Dependabot::Experiments.enabled?(:enable_private_registry_for_corepack)

          registry, token = find_registry_and_token

          env = {}
          env["COREPACK_NPM_REGISTRY"] = registry if registry
          env["COREPACK_NPM_TOKEN"] = token if token
          env
        end

        sig { returns([T.nilable(String), T.nilable(String)]) }
        def find_registry_and_token
          # Priority: credentials > .npmrc > .yarnrc > .yarnrc.yml
          registry, token = extract_from_credentials
          return [registry, token] if registry

          npmrc = dependency_files.find { |f| f.name.end_with?(".npmrc") }
          if npmrc
            registry, token = extract_from_npmrc(npmrc)
            return [registry, token] if registry
          end

          yarnrc = dependency_files.find { |f| f.name.end_with?(".yarnrc") }
          if yarnrc
            registry, token = extract_from_yarnrc(yarnrc)
            return [registry, token] if registry
          end

          yarnrc_yml = dependency_files.find { |f| f.name.end_with?(".yarnrc.yml") }
          if yarnrc_yml
            registry, token = extract_from_yarnrc_yml(yarnrc_yml)
            return [registry, token] if registry
          end

          [nil, nil]
        end

        sig { returns([T.nilable(String), T.nilable(String)]) }
        def extract_from_credentials
          credentials.each do |cred|
            next unless cred["type"] == "npm_registry"
            next unless cred.replaces_base?

            registry = T.let(cred["registry"], T.nilable(String))
            token = T.let(cred["token"], T.nilable(String))

            if registry && !registry.start_with?("http://", "https://")
              registry = "https://#{registry}"
            end

            return [registry, token]
          end

          [nil, nil]
        end

        sig { params(npmrc_file: Dependabot::DependencyFile).returns([T.nilable(String), T.nilable(String)]) }
        def extract_from_npmrc(npmrc_file)
          content = T.let(npmrc_file.content, T.nilable(String))
          return [nil, nil] unless content

          registry = T.let(content[/^registry\s*=\s*(.+)$/, 1], T.nilable(String))
          registry = registry&.strip
          token = T.let(content[/^_authToken\s*=\s*(.+)$/, 1], T.nilable(String))
          token = token&.strip

          [registry, token]
        end

        sig { params(yarnrc_file: Dependabot::DependencyFile).returns([T.nilable(String), T.nilable(String)]) }
        def extract_from_yarnrc(yarnrc_file)
          content = T.let(yarnrc_file.content, T.nilable(String))
          return [nil, nil] unless content

          registry = T.let(content[/^registry\s+"(.+)"$/, 1], T.nilable(String))
          registry = registry&.strip
          token = T.let(content[/^"?_authToken"?\s+"(.+)"$/, 1], T.nilable(String))
          token = token&.strip

          [registry, token]
        end

        sig { params(yarnrc_yml_file: Dependabot::DependencyFile).returns([T.nilable(String), T.nilable(String)]) }
        def extract_from_yarnrc_yml(yarnrc_yml_file)
          content = T.let(yarnrc_yml_file.content, T.nilable(String))
          return [nil, nil] unless content

          parsed_data = T.unsafe(YAML.safe_load(content, permitted_classes: [Symbol, String]))
          parsed = parsed_data.is_a?(Hash) ? parsed_data : {}

          registry = T.cast(parsed["npmRegistryServer"], T.nilable(String))
          token = T.cast(parsed["npmAuthToken"], T.nilable(String))

          [registry, token]
        rescue Psych::SyntaxError
          [nil, nil]
        end
      end
    end
  end
end
