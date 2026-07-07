# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/nub/helpers"
require "dependabot/nub/package/registry_finder"
require "dependabot/nub/registry_parser"
require "dependabot/npm_and_yarn/file_updater/pnpm_lockfile_updater"
require "dependabot/shared_helpers"

module Dependabot
  module Nub
    class FileUpdater < Dependabot::FileUpdaters::Base
      class NubLockfileUpdater
        extend T::Sig

        require_relative "npmrc_builder"
        require_relative "package_json_updater"

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { params(nub_lock: Dependabot::DependencyFile).returns(String) }
        def updated_nub_lock_content(nub_lock)
          @updated_nub_lock_content ||= T.let({}, T.nilable(T::Hash[String, String]))
          return T.must(@updated_nub_lock_content[nub_lock.name]) if @updated_nub_lock_content[nub_lock.name]

          new_content = run_nub_update(nub_lock: nub_lock)
          @updated_nub_lock_content[nub_lock.name] = new_content
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_nub_lock_updater_error(e, nub_lock)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        ERR_PATTERNS = T.let(
          {
            /get .* 404/i => Dependabot::DependencyNotFound,
            /installfailed cloning repository/i => Dependabot::DependencyNotFound,
            /file:.* failed to resolve/i => Dependabot::DependencyNotFound,
            /no version matching/i => Dependabot::DependencyFileNotResolvable,
            /failed to resolve/i => Dependabot::DependencyFileNotResolvable
          }.freeze,
          T::Hash[Regexp, Dependabot::DependabotError]
        )

        sig { params(nub_lock: Dependabot::DependencyFile).returns(String) }
        def run_nub_update(nub_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(nub_lock))

            SharedHelpers.with_git_configured(credentials: credentials) do
              # nub is pnpm-compatible and has no `install <pkg>@<ver>` add nor a `update <pkg>@<ver>`
              # that targets an arbitrary version. To pin each dependency to the exact version
              # Dependabot chose, temporarily rewrite the manifests with that exact version and run a
              # lockfile-only install (nub pins it), then restore the final requirement and install
              # again — nub's lockfile-only install is conservative, so it keeps the already-locked
              # version and only rewrites the specifier to match the final requirement.
              write_pinned_package_json_files
              run_nub_install

              write_final_package_json_files
              run_nub_install

              File.read(nub_lock.name)
            end
          end
        end

        sig { void }
        def run_nub_install
          Helpers.run_nub_command(
            "install --lockfile-only --ignore-scripts",
            fingerprint: "install --lockfile-only --ignore-scripts"
          )
        end

        # Write each manifest with the updated registry dependencies pinned to their exact target
        # version, so the subsequent lockfile-only install resolves to precisely that version.
        sig { void }
        def write_pinned_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, pinned_package_json_content(file))
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def pinned_package_json_content(file)
          parsed = JSON.parse(updated_package_json_content(file))

          %w(dependencies devDependencies optionalDependencies peerDependencies).each do |group|
            group_deps = parsed[group]
            next unless group_deps.is_a?(Hash)

            dependencies.each do |dep|
              next if git_dependency?(dep)

              version = dep.version
              next unless version && group_deps.key?(dep.name)

              group_deps[dep.name] = version
            end
          end

          JSON.pretty_generate(parsed)
        end

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def git_dependency?(dependency)
          dependency.requirements.any? { |req| req[:source] && req[:source][:type] == "git" }
        end

        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Dependency]]))
          @lockfile_dependencies[lockfile.name] ||=
            Nub::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        sig do
          params(error: SharedHelpers::HelperSubprocessFailed, _nub_lock: Dependabot::DependencyFile)
            .returns(T.noreturn)
        end
        def handle_nub_lock_updater_error(error, _nub_lock)
          # nub.lock is pnpm-lock v9 and nub surfaces pnpm-format engine errors, so map them
          # through npm_and_yarn's pnpm handler (duplicates, no-versions, ECONNRESET, ...) before
          # falling back to nub's own registry/network patterns below.
          Dependabot::NpmAndYarn::PnpmErrorHandler.new(
            dependencies: dependencies,
            dependency_files: dependency_files
          ).handle_pnpm_error(error)

          error_message = error.message
          ERR_PATTERNS.each do |pattern, error_class|
            raise error_class, error_message if error_message.match?(pattern)
          end

          raise error
        end

        sig { void }
        def write_final_package_json_files
          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, updated_package_json_content(file))
          end
        end

        sig { params(nub_lock: Dependabot::DependencyFile).returns(String) }
        def npmrc_content(nub_lock)
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files,
            dependencies: lockfile_dependencies(nub_lock)
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
  end
end
