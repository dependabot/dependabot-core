# typed: true
# frozen_string_literal: true

require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/update_checker/registry_finder"
require "dependabot/npm_and_yarn/registry_parser"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class PnpmLockfileUpdater
        require_relative "npmrc_builder"
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

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :repo_contents_path
        attr_reader :credentials

        IRRESOLVABLE_PACKAGE = "ERR_PNPM_NO_MATCHING_VERSION"
        INVALID_REQUIREMENT = "ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER"
        UNREACHABLE_GIT = %r{ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<url>https://codeload\.github\.com/[^/]+/[^/]+)/}
        FORBIDDEN_PACKAGE = /ERR_PNPM_FETCH_403[ [^:print:]]+GET (?<dependency_url>.*): Forbidden - 403/
        MISSING_PACKAGE = /ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<dependency_url>.*): Not Found - 404/
        UNAUTHORIZED_PACKAGE = /ERR_PNPM_FETCH_401[ [^:print:]]+GET (?<dependency_url>.*): Unauthorized - 401/
        MISSING_PACKAGE_IN_REPO = /ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<dependency_url>.*):  - 404/

        def run_pnpm_update(pnpm_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(pnpm_lock))

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

          Helpers.run_pnpm_command(
            "install #{dependency_updates} --lockfile-only --ignore-workspace-root-check",
            fingerprint: "install <dependency_updates> --lockfile-only --ignore-workspace-root-check"
          )
        end

        def run_pnpm_install
          Helpers.run_pnpm_command(
            "install --lockfile-only"
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

          if error_message.match?(UNREACHABLE_GIT)
            url = error_message.match(UNREACHABLE_GIT).named_captures.fetch("url")

            raise Dependabot::GitDependenciesNotReachable, url
          end

          [FORBIDDEN_PACKAGE, MISSING_PACKAGE, UNAUTHORIZED_PACKAGE, MISSING_PACKAGE_IN_REPO].each do |regexp|
            next unless error_message.match?(regexp)

            dependency_url = error_message.match(regexp).named_captures["dependency_url"]

            raise_package_access_error(dependency_url, pnpm_lock)
          end

          raise
        end

        def raise_resolvability_error(error_message, pnpm_lock)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{pnpm_lock.path}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def raise_package_access_error(dependency_url, pnpm_lock)
          package_name = RegistryParser.new(resolved_url: dependency_url, credentials: credentials).dependency_name
          missing_dep = lockfile_dependencies(pnpm_lock)
                        .find { |dep| dep.name == package_name }

          raise PrivateSourceAuthenticationFailure, package_name unless missing_dep

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

        def npmrc_content(pnpm_lock)
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files,
            dependencies: lockfile_dependencies(pnpm_lock)
          ).npmrc_content
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
