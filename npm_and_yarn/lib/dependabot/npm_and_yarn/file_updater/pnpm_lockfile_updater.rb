# frozen_string_literal: true

require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileUpdater
      class PnpmLockfileUpdater
        require_relative "package_json_updater"

        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        def updated_pnpm_lock_content(pnpm_lock)
          @updated_pnpm_lock_content ||= {}
          return @updated_pnpm_lock_content[pnpm_lock.name] if @updated_pnpm_lock_content[pnpm_lock.name]

          new_content = run_pnpm_update(pnpm_lock: pnpm_lock)
          @updated_pnpm_lock_content[pnpm_lock.name] = new_content
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_pnpm_lock_updater_error(e, pnpm_lock)
        end

        private

        attr_reader :dependencies, :dependency_files, :repo_contents_path, :credentials

        IRRESOLVABLE_PACKAGE = "ERR_PNPM_NO_MATCHING_VERSION"
        INVALID_REQUIREMENT = "ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER"
        MISSING_PACKAGE = /(?<package_req>.*?) is not in the npm registry, or you have no permission to fetch it/

        def run_pnpm_update(pnpm_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              run_pnpm_updater

              write_final_package_json_files

              run_pnpm_install

              File.read(pnpm_lock.name)
            end
          end
        end

        def run_pnpm_updater
          dependency_updates = dependencies.map do |d|
            "#{d.name}@#{d.version}"
          end.join(" ")

          SharedHelpers.run_shell_command(
            "pnpm install #{dependency_updates} --lockfile-only --ignore-workspace-root-check",
            fingerprint: "pnpm install <dependency_updates> --lockfile-only --ignore-workspace-root-check"
          )
        end

        def run_pnpm_install
          SharedHelpers.run_shell_command(
            "pnpm install --lockfile-only"
          )
        end

        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= {}
          @lockfile_dependencies[lockfile.name] ||=
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        def handle_pnpm_lock_updater_error(error, pnpm_lock)
          error_message = error.message

          if error_message.include?(IRRESOLVABLE_PACKAGE) || error_message.include?(INVALID_REQUIREMENT)
            raise_resolvability_error(error_message, pnpm_lock)
          end

          raise unless error_message.match?(MISSING_PACKAGE)

          package_name = error_message.match(MISSING_PACKAGE).
                         named_captures["package_req"].
                         split(/(?<=\w)\@/).first
          raise_missing_package_error(package_name, error_message, pnpm_lock)
        end

        def raise_resolvability_error(error_message, pnpm_lock)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{pnpm_lock.path}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def raise_missing_package_error(package_name, _error_message, pnpm_lock)
          missing_dep = lockfile_dependencies(pnpm_lock).
                        find { |dep| dep.name == package_name }

          reg = NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: npmrc_file
          ).registry

          raise PrivateSourceAuthenticationFailure, reg
        end

        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        def updated_package_json_content(file)
          @updated_package_json_content ||= {}
          @updated_package_json_content[file.name] ||=
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: dependencies
            ).updated_package_json.content
        end

        def package_files
          @package_files ||= dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def base_dir
          dependency_files.first.directory
        end

        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end
      end
    end
  end
end
