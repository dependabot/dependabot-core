# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/package/registry_finder"
require "dependabot/npm_and_yarn/registry_parser"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      # rubocop:disable Metrics/ClassLength
      class PnpmLockfileUpdater
        extend T::Sig

        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: T.nilable(String),
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @error_handler = T.let(
            PnpmErrorHandler.new(
              dependencies: dependencies,
              dependency_files: dependency_files
            ),
            PnpmErrorHandler
          )
        end

        sig do
          params(
            pnpm_lock: Dependabot::DependencyFile,
            updated_pnpm_workspace_content: T.nilable(T::Hash[String, T.nilable(String)])
          ).returns(String)
        end
        def updated_pnpm_lock_content(pnpm_lock, updated_pnpm_workspace_content: nil)
          @updated_pnpm_lock_content ||= T.let(
            {},
            T.nilable(T::Hash[String, String])
          )
          return T.must(@updated_pnpm_lock_content[pnpm_lock.name]) if @updated_pnpm_lock_content[pnpm_lock.name]

          new_content = run_pnpm_update(
            pnpm_lock: pnpm_lock,
            updated_pnpm_workspace_content: updated_pnpm_workspace_content
          )
          @updated_pnpm_lock_content[pnpm_lock.name] = new_content
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_pnpm_lock_updater_error(e, pnpm_lock)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(PnpmErrorHandler) }
        attr_reader :error_handler

        IRRESOLVABLE_PACKAGE = "ERR_PNPM_NO_MATCHING_VERSION"
        INVALID_REQUIREMENT = "ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER"
        UNREACHABLE_GIT = %r{Command failed with exit code 128: git ls-remote (?<url>.*github\.com/[^/]+/[^ ]+)}
        UNREACHABLE_GIT_V8 = %r{ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<url>https://codeload\.github\.com/[^/]+/[^/]+)/}
        FORBIDDEN_PACKAGE = /ERR_PNPM_FETCH_403[ [^:print:]]+GET (?<dependency_url>.*): Forbidden - 403/
        MISSING_PACKAGE = /ERR_PNPM_FETCH_404[ [^:print:]]+GET (?<dependency_url>.*): (?:Not Found)? - 404/
        UNAUTHORIZED_PACKAGE = /ERR_PNPM_FETCH_401[ [^:print:]]+GET (?<dependency_url>.*): Unauthorized - 401/

        # ERR_PNPM_FETCH ERROR CODES
        ERR_PNPM_FETCH_401 = /ERR_PNPM_FETCH_401.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_403 = /ERR_PNPM_FETCH_403.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_404 = /ERR_PNPM_FETCH_404.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_500 = /ERR_PNPM_FETCH_500.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_502 = /ERR_PNPM_FETCH_502.*GET (?<dependency_url>.*):/
        ERR_PNPM_FETCH_503 = /ERR_PNPM_FETCH_503.*GET (?<dependency_url>.*):/

        # ERR_PNPM_UNSUPPORTED_ENGINE
        ERR_PNPM_UNSUPPORTED_ENGINE = /ERR_PNPM_UNSUPPORTED_ENGINE/
        PACAKGE_MANAGER = /Your (?<pkg_mgr>.*) version is incompatible with/
        VERSION_REQUIREMENT = /Expected version: (?<supported_ver>.*)\nGot: (?<detected_ver>.*)\n/

        ERR_PNPM_TARBALL_INTEGRITY = /ERR_PNPM_TARBALL_INTEGRITY/

        ERR_PNPM_PATCH_NOT_APPLIED = /ERR_PNPM_PATCH_NOT_APPLIED/

        # this intermittent issue is related with Node v20
        ERR_INVALID_THIS = /ERR_INVALID_THIS/
        URL_SEARCH_PARAMS = /URLSearchParams/

        # A modules directory is present and is linked to a different store directory.
        ERR_PNPM_UNEXPECTED_STORE = /ERR_PNPM_UNEXPECTED_STORE/

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

        # Unparsable package.json file
        ERR_PNPM_INVALID_PACKAGE_JSON = /Invalid package.json in package/

        # Unparsable lockfile
        ERR_PNPM_UNEXPECTED_PKG_CONTENT_IN_STORE = /ERR_PNPM_UNEXPECTED_PKG_CONTENT_IN_STORE/
        ERR_PNPM_OUTDATED_LOCKFILE = /ERR_PNPM_OUTDATED_LOCKFILE/

        # Peer dependencies configuration error
        ERR_PNPM_PEER_DEP_ISSUES = /ERR_PNPM_PEER_DEP_ISSUES/

        sig do
          params(
            pnpm_lock: Dependabot::DependencyFile,
            updated_pnpm_workspace_content: T.nilable(T::Hash[String, T.nilable(String)])
          )
            .returns(String)
        end
        def run_pnpm_update(pnpm_lock:, updated_pnpm_workspace_content: nil)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(pnpm_lock))

            SharedHelpers.with_git_configured(credentials: credentials) do
              if updated_pnpm_workspace_content
                File.write("pnpm-workspace.yaml", updated_pnpm_workspace_content["pnpm-workspace.yaml"])
              else
                run_pnpm_update_packages
                write_final_package_json_files
              end

              run_pnpm_install

              File.read(pnpm_lock.name)
            end
          end
        end

        sig { returns(T.nilable(String)) }
        def run_pnpm_update_packages
          dependency_updates = dependencies.map do |d|
            "#{d.name}@#{d.version}"
          end.join(" ")

          Helpers.run_pnpm_command(
            "install #{dependency_updates} --lockfile-only -r",
            fingerprint: "install <dependency_updates> --lockfile-only -r"
          )
        end

        sig { returns(T.nilable(String)) }
        def run_pnpm_install
          Helpers.run_pnpm_command(
            "install --lockfile-only"
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_files
          @workspace_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("pnpm-workspace.yaml") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Dependency]]))
          @lockfile_dependencies[lockfile.name] ||=
            NpmAndYarn::FileParser.new(
              dependency_files: [lockfile, *package_files, *workspace_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/MethodLength
        # rubocop:disable Metrics/CyclomaticComplexity
        sig do
          params(
            error: SharedHelpers::HelperSubprocessFailed,
            pnpm_lock: Dependabot::DependencyFile
          )
            .returns(T.noreturn)
        end
        def handle_pnpm_lock_updater_error(error, pnpm_lock)
          error_message = error.message

          if error_message.include?(IRRESOLVABLE_PACKAGE) || error_message.include?(INVALID_REQUIREMENT)
            raise_resolvability_error(error_message, pnpm_lock)
          end

          if error_message.match?(UNREACHABLE_GIT)
            url = error_message.match(UNREACHABLE_GIT)&.named_captures&.fetch("url")&.gsub("git+ssh://git@", "https://")&.delete_suffix(".git")

            raise Dependabot::GitDependenciesNotReachable, T.must(url)
          end

          if error_message.match?(UNREACHABLE_GIT_V8)
            url = error_message.match(UNREACHABLE_GIT_V8)&.named_captures&.fetch("url")&.gsub("codeload.", "")

            raise Dependabot::GitDependenciesNotReachable, T.must(url)
          end

          [FORBIDDEN_PACKAGE, MISSING_PACKAGE, UNAUTHORIZED_PACKAGE, ERR_PNPM_FETCH_401,
           ERR_PNPM_FETCH_403, ERR_PNPM_FETCH_404, ERR_PNPM_FETCH_500, ERR_PNPM_FETCH_502, ERR_PNPM_FETCH_503]
            .each do |regexp|
            next unless error_message.match?(regexp)

            dependency_url = T.must(error_message.match(regexp)&.named_captures&.[]("dependency_url"))
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
            dir = error_message.match(ERR_PNPM_LINKED_PKG_DIR_NOT_FOUND)&.named_captures&.fetch("dir")
            msg = "Could not find linked package installation directory \"#{dir&.split('/')&.last}\""
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_INVALID_PACKAGE_JSON) || error_message.match?(ERR_PNPM_UNEXPECTED_STORE)
            msg = "Error while resolving package.json."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          [ERR_PNPM_UNEXPECTED_PKG_CONTENT_IN_STORE, ERR_PNPM_OUTDATED_LOCKFILE]
            .each do |regexp|
            next unless error_message.match?(regexp)

            error_msg = T.let("Error while resolving pnpm-lock.yaml file.", String)

            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, error_msg
          end

          if error_message.match?(ERR_PNPM_PEER_DEP_ISSUES)
            msg = "Missing or invalid configuration while installing peer dependencies."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          raise_patch_dependency_error(error_message) if error_message.match?(ERR_PNPM_PATCH_NOT_APPLIED)
          raise_unsupported_engine_error(error_message, pnpm_lock) if error_message.match?(ERR_PNPM_UNSUPPORTED_ENGINE)

          if error_message.match?(ERR_INVALID_THIS) && error_message.match?(URL_SEARCH_PARAMS)
            msg = "Error while resolving dependencies."
            Dependabot.logger.warn(error_message)
            raise Dependabot::DependencyFileNotResolvable, msg
          end

          if error_message.match?(ERR_PNPM_UNSUPPORTED_PLATFORM)
            raise_unsupported_platform_error(error_message, pnpm_lock)
          end

          error_handler.handle_pnpm_error(error)

          raise
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/MethodLength
        # rubocop:enable Metrics/CyclomaticComplexity

        sig { params(error_message: String, pnpm_lock: Dependabot::DependencyFile).returns(T.noreturn) }
        def raise_resolvability_error(error_message, pnpm_lock)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error whilst updating #{dependency_names} in " \
                "#{pnpm_lock.path}:\n#{error_message}"
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        sig { params(error_message: String).returns(T.noreturn) }
        def raise_patch_dependency_error(error_message)
          dependency_names = dependencies.map(&:name).join(", ")
          msg = "Error while updating \"#{dependency_names}\" in " \
                "update group \"patchedDependencies\"."
          Dependabot.logger.warn(error_message)
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        sig do
          params(
            error_message: String,
            _pnpm_lock: Dependabot::DependencyFile
          ).returns(T.nilable(T.noreturn))
        end
        def raise_unsupported_engine_error(error_message, _pnpm_lock)
          match_pkg_mgr = error_message.match(PACAKGE_MANAGER)
          match_version = error_message.match(VERSION_REQUIREMENT)

          unless match_pkg_mgr && match_version &&
                 match_pkg_mgr.named_captures && match_version.named_captures
            return nil
          end

          captures_pkg_mgr = match_pkg_mgr.named_captures
          captures_version = match_version.named_captures

          pkg_mgr = captures_pkg_mgr["pkg_mgr"]
          supported_ver = captures_version["supported_ver"]
          detected_ver = captures_version["detected_ver"]

          if pkg_mgr && supported_ver && detected_ver
            raise Dependabot::ToolVersionNotSupported.new(
              pkg_mgr,
              supported_ver,
              detected_ver
            )
          end

          nil
        end

        sig do
          params(
            error_message: String,
            dependency_url: String,
            pnpm_lock: Dependabot::DependencyFile
          )
            .returns(T.noreturn)
        end
        def raise_package_access_error(error_message, dependency_url, pnpm_lock)
          package_name = RegistryParser.new(resolved_url: dependency_url,
                                            credentials: credentials).dependency_name
          missing_dep = lockfile_dependencies(pnpm_lock)
                        .find { |dep| dep.name == package_name }
          raise DependencyNotFound, package_name unless missing_dep

          reg = Package::RegistryFinder.new(
            dependency: missing_dep,
            credentials: credentials,
            npmrc_file: npmrc_file
          ).registry
          Dependabot.logger.warn("Error while accessing #{reg}. Response (truncated) - #{error_message[0..500]}...")
          raise PrivateSourceAuthenticationFailure, reg
        end

        sig { void }
        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        sig do
          params(
            error_message: String,
            _pnpm_lock: Dependabot::DependencyFile
          )
            .returns(T.nilable(T.noreturn))
        end
        def raise_unsupported_platform_error(error_message, _pnpm_lock)
          match_dep = error_message.match(PLATFORM_PACAKGE_DEP)
          match_version = error_message.match(PLATFORM_VERSION_REQUIREMENT)

          unless match_dep && match_version &&
                 match_dep.named_captures && match_version.named_captures
            return nil
          end

          captures_version = match_version.named_captures

          supported_ver = captures_version["supported_ver"]
          detected_ver = captures_version["detected_ver"]

          if supported_ver && detected_ver
            supported_version = sanitize_message(supported_ver)
            detected_version = sanitize_message(detected_ver)

            Dependabot.logger.warn(error_message)
            raise Dependabot::ToolVersionNotSupported.new(
              PLATFORM_PACAKGE_MANAGER,
              supported_version,
              detected_version
            )
          end

          nil
        end

        sig { params(pnpm_lock: Dependabot::DependencyFile).returns(String) }
        def npmrc_content(pnpm_lock)
          NpmrcBuilder.new(
            credentials: T.unsafe(credentials),
            dependency_files: dependency_files,
            dependencies: lockfile_dependencies(pnpm_lock)
          ).npmrc_content
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_package_json_content(file)
          @updated_package_json_content ||= T.let({}, T.nilable(T::Hash[String, String]))
          @updated_package_json_content[file.name] ||=
            T.must(
              PackageJsonUpdater.new(
                package_json: file,
                dependencies: dependencies
              ).updated_package_json.content
            )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            dependency_files.select { |f| f.name.end_with?("package.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(String) }
        def base_dir
          T.must(dependency_files.first).directory
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def npmrc_file
          dependency_files.find { |f| f.name == ".npmrc" }
        end

        sig { params(message: String).returns(String) }
        def sanitize_message(message)
          message.gsub(/"|\[|\]|\}|\{/, "")
        end
      end
    end
    # rubocop:enable Metrics/ClassLength

    class PnpmErrorHandler
      extend T::Sig

      # remote connection closed
      ECONNRESET_ERROR = /ECONNRESET/

      # socket hang up error code
      SOCKET_HANG_UP = /socket hang up/

      # ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC error
      ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC = /ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC/

      # duplicate package error code
      DUPLICATE_PACKAGE = /Found duplicates/

      ERR_PNPM_NO_VERSIONS = /ERR_PNPM_NO_VERSIONS/

      # Initializes the YarnErrorHandler with dependencies and dependency files
      sig do
        params(
          dependencies: T::Array[Dependabot::Dependency],
          dependency_files: T::Array[Dependabot::DependencyFile]
        )
          .void
      end
      def initialize(dependencies:, dependency_files:)
        @dependencies = dependencies
        @dependency_files = dependency_files
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      public

      # Handles errors with specific to yarn error codes
      sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
      def handle_pnpm_error(error)
        if error.message.match?(DUPLICATE_PACKAGE) || error.message.match?(ERR_PNPM_NO_VERSIONS) ||
           error.message.match?(ERR_PNPM_CATALOG_ENTRY_NOT_FOUND_FOR_SPEC)

          raise DependencyFileNotResolvable, "Error resolving dependency"
        end

        ## Clean error message from ANSI escape codes
        return unless error.message.match?(ECONNRESET_ERROR) || error.message.match?(SOCKET_HANG_UP)

        raise InconsistentRegistryResponse, "Inconsistent registry response while resolving dependency"
      end
    end
  end
end
