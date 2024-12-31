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
          if dependencies[0].name == 'styled-components'
            # debugger
          end

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
        UNREACHABLE_GIT = %r{Command failed with exit code 128: git ls-remote (?<url>.*github\.com/[^/]+/[^ ]+)}
        UNREACHABLE_GIT_V8 = %r{ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<url>https://codeload\.github\.com/[^/]+/[^/]+)/}
        FORBIDDEN_PACKAGE = /ERR_PNPM_FETCH_403[ [^:print:]]+GET (?<dependency_url>.*): Forbidden - 403/
        MISSING_PACKAGE = /ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<dependency_url>.*): (?:Not Found)? - 404/
        UNAUTHORIZED_PACKAGE = /ERR_PNPM_FETCH_401[ [^:print:]]+GET (?<dependency_url>.*): Unauthorized - 401/

        # ERR_PNPM_FETCH ERROR CODES
        ERR_PNPM_FETCH_401 = /ERR_PNPM_FETCH_401.*GET (?<dependency_url>.*):  - 401/
        ERR_PNPM_FETCH_403 = /ERR_PNPM_FETCH_403.*GET (?<dependency_url>.*):  - 403/
        ERR_PNPM_FETCH_404 = /ERR_PNPM_FETCH_404.*GET (?<dependency_url>.*):  - 404/
        ERR_PNPM_FETCH_500 = /ERR_PNPM_FETCH_500.*GET (?<dependency_url>.*):  - 500/
        ERR_PNPM_FETCH_502 = /ERR_PNPM_FETCH_502.*GET (?<dependency_url>.*):  - 502/
        ERR_PNPM_FETCH_503 = /ERR_PNPM_FETCH_503.*GET (?<dependency_url>.*):  - 503/

        # ERR_PNPM_UNSUPPORTED_ENGINE
        ERR_PNPM_UNSUPPORTED_ENGINE = /ERR_PNPM_UNSUPPORTED_ENGINE/
        PACAKGE_MANAGER = /Your (?<pkg_mgr>.*) version is incompatible with/
        VERSION_REQUIREMENT = /Expected version: (?<supported_ver>.*)\nGot: (?<detected_ver>.*)\n/

        ERR_PNPM_TARBALL_INTEGRITY = /ERR_PNPM_TARBALL_INTEGRITY/

        ERR_PNPM_PATCH_NOT_APPLIED = /ERR_PNPM_PATCH_NOT_APPLIED/

        # ERR_PNPM_UNSUPPORTED_PLATFORM
        ERR_PNPM_UNSUPPORTED_PLATFORM = /ERR_PNPM_UNSUPPORTED_PLATFORM/
        PLATFORM_PACAKGE_DEP = /Unsupported platform for (?<dep>.*)\: wanted/
        PLATFORM_VERSION_REQUIREMENT = /wanted {(?<supported_ver>.*)} \(current: (?<detected_ver>.*)\)/
        PLATFORM_PACAKGE_MANAGER = "pnpm"

        INVALID_PACKAGE_SPEC = /Invalid package manager specification/

        # Metadata inconsistent error codes
        ERR_PNPM_META_FETCH_FAIL = /ERR_PNPM_META_FETCH_FAIL/
        ERR_PNPM_BROKEN_METADATA_JSON = /ERR_PNPM_BROKEN_METADATA_JSON/

        # Directory related error codes
        ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND = /ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND*.*Could not install from \"(?<dir>.*)\" /
        ERR_PNPM_WORKSPACE_PKG_NOT_FOUND = /ERR_PNPM_WORKSPACE_PKG_NOT_FOUND/

        def run_pnpm_update(pnpm_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(pnpm_lock))

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_pnpm_update_packages

              write_final_package_json_files

              run_pnpm_install

              File.read(pnpm_lock.name)
            end
          end
        end

        def run_pnpm_update_packages
          dependency_updates = dependencies.map do |d|
            "#{d.name}@#{d.version}"
          end.join(" ")

          Helpers.run_pnpm_command(
            "up #{dependency_updates} --lockfile-only",
            fingerprint: "up <dependency_updates> --lockfile-only"
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

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/CyclomaticComplexity
        def handle_pnpm_lock_updater_error(error, pnpm_lock)
          error_message = error.message

          if error_message.include?(IRRESOLVABLE_PACKAGE) || error_message.include?(INVALID_REQUIREMENT)
            raise_resolvability_error(error_message, pnpm_lock)
          end

          if error_message.match?(UNREACHABLE_GIT)
            url = error_message.match(UNREACHABLE_GIT).named_captures.fetch("url").gsub("git+ssh://git@", "https://").delete_suffix(".git")

            raise Dependabot::GitDependenciesNotReachable, url
          end

          if error_message.match?(UNREACHABLE_GIT_V8)
            url = error_message.match(UNREACHABLE_GIT_V8).named_captures.fetch("url").gsub("codeload.", "")

            raise Dependabot::GitDependenciesNotReachable, url
          end

          [FORBIDDEN_PACKAGE, MISSING_PACKAGE, UNAUTHORIZED_PACKAGE, ERR_PNPM_FETCH_401,
           ERR_PNPM_FETCH_403, ERR_PNPM_FETCH_404, ERR_PNPM_FETCH_500, ERR_PNPM_FETCH_502, ERR_PNPM_FETCH_503]
            .each do |regexp|
            next unless error_message.match?(regexp)

            dependency_url = error_message.match(regexp).named_captures["dependency_url"]
            raise_package_access_error(error_message, dependency_url, pnpm_lock)
          end

          # TO-DO : subclassifcation of ERR_PNPM_TARBALL_INTEGRITY errors
          if error_message.match?(ERR_PNPM_TARBALL_INTEGRITY)
            dependency_names = dependencies.map(&:name).join(", ")

            msg = "Error (ERR_PNPM_TARBALL_INTEGRITY) while resolving \"#{dependency_names}\"."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          # TO-DO : investigate "packageManager" allowed regex
          if error_message.match?(INVALID_PACKAGE_SPEC)
            dependency_names = dependencies.map(&:name).join(", ")

            msg = "Invalid package manager specification in package.json while resolving \"#{dependency_names}\"."
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_META_FETCH_FAIL)

            msg = error_message.split(ERR_PNPM_META_FETCH_FAIL).last
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_WORKSPACE_PKG_NOT_FOUND)
            dependency_names = dependencies.map(&:name).join(", ")

            msg = "No package named \"#{dependency_names}\" present in workspace."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_BROKEN_METADATA_JSON)
            msg = "Error (ERR_PNPM_BROKEN_METADATA_JSON) while resolving \"pnpm-lock.yaml\" file."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND)
            dir = error_message.match(ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND).named_captures.fetch("dir")
            msg = "Could not find linked package installation directory \"#{dir.split('/').last}\""
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          raise_patch_dependency_error(error_message) if error_message.match?(ERR_PNPM_PATCH_NOT_APPLIED)

          raise_unsupported_engine_error(error_message, pnpm_lock) if error_message.match?(ERR_PNPM_UNSUPPORTED_ENGINE)

          if error_message.match?(ERR_PNPM_UNSUPPORTED_PLATFORM)
            raise_unsupported_platform_error(error_message,
                                             pnpm_lock)
          end

          raise
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/CyclomaticComplexity

        def raise_resolvability_error(error_message, pnpm_lock)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{pnpm_lock.path}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def raise_patch_dependency_error(error_message)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error while updating \"#{dependency_names}\" in " \
                "update group \"patchedDependencies\"."
          Dependabot.logger.warn(error_message)
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def raise_unsupported_engine_error(error_message, _pnpm_lock)
          unless error_message.match(PACAKGE_MANAGER) &&
                 error_message.match(VERSION_REQUIREMENT)
            return
          end

          package_manager = error_message.match(PACAKGE_MANAGER).named_captures["pkg_mgr"]
          supported_version = error_message.match(VERSION_REQUIREMENT).named_captures["supported_ver"]
          detected_version = error_message.match(VERSION_REQUIREMENT).named_captures["detected_ver"]

          raise Dependabot::ToolVersionNotSupported.new(package_manager, supported_version, detected_version)
        end

        def raise_package_access_error(error_message, dependency_url, pnpm_lock)
          package_name = RegistryParser.new(resolved_url: dependency_url, credentials: credentials).dependency_name
          missing_dep = lockfile_dependencies(pnpm_lock)
                        .find { |dep| dep.name == package_name }
          raise DependencyNotFound, package_name unless missing_dep

          reg = NpmAndYarn::UpdateChecker::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: npmrc_file
          ).registry
          Dependabot.logger.warn("Error while accessing #{reg}. Response (truncated) - #{error_message[0..500]}...")
          raise PrivateSourceAuthenticationFailure, reg
        end

        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        def raise_unsupported_platform_error(error_message, _pnpm_lock)
          unless error_message.match(PLATFORM_PACAKGE_DEP) &&
                 error_message.match(PLATFORM_VERSION_REQUIREMENT)
            return
          end

          supported_version = error_message.match(PLATFORM_VERSION_REQUIREMENT)
                                           .named_captures["supported_ver"]
                                           .then { sanitize_message(_1) }
          detected_version = error_message.match(PLATFORM_VERSION_REQUIREMENT)
                                          .named_captures["detected_ver"]
                                          .then { sanitize_message(_1) }

          Dependabot.logger.warn(error_message)
          raise Dependabot::ToolVersionNotSupported.new(PLATFORM_PACAKGE_MANAGER, supported_version, detected_version)
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

        def sanitize_message(message)
          message.gsub(/"|\[|\]|\}|\{/, "")
        end
      end
    end
  end
end
