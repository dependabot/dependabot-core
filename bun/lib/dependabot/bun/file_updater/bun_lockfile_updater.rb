# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/bun/helpers"
require "dependabot/bun/package/registry_finder"
require "dependabot/bun/registry_parser"
require "dependabot/shared_helpers"

module Dependabot
  module Bun
    class FileUpdater < Dependabot::FileUpdaters::Base
      class BunLockfileUpdater
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

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def updated_bun_lock_content(bun_lock)
          @updated_bun_lock_content ||= T.let({}, T.nilable(T::Hash[String, String]))
          return T.must(@updated_bun_lock_content[bun_lock.name]) if @updated_bun_lock_content[bun_lock.name]

          new_content = run_bun_update(bun_lock: bun_lock)
          @updated_bun_lock_content[bun_lock.name] = new_content
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_bun_lock_updater_error(e, bun_lock)
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

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def run_bun_update(bun_lock:)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            File.write(".npmrc", npmrc_content(bun_lock))

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_bun_updater

              write_final_package_json_files

              run_bun_install

              File.read(bun_lock.name)
            end
          end
        end

        sig { void }
        def run_bun_updater
          dependency_updates = dependencies.map do |d|
            "#{d.name}@#{d.version}"
          end.join(" ")

          Helpers.run_bun_command(
            "install #{dependency_updates} --save-text-lockfile",
            fingerprint: "install <dependency_updates> --save-text-lockfile"
          )
        end

        sig { void }
        def run_bun_install
          Helpers.run_bun_command(
            "install --save-text-lockfile"
          )
        end

        sig { params(lockfile: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
        def lockfile_dependencies(lockfile)
          @lockfile_dependencies ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Dependency]]))
          @lockfile_dependencies[lockfile.name] ||=
            Bun::FileParser.new(
              dependency_files: [lockfile, *package_files],
              source: nil,
              credentials: credentials
            ).parse
        end

        sig { params(error: Dependabot::DependabotError, _bun_lock: Dependabot::DependencyFile).returns(T.noreturn) }
        def handle_bun_lock_updater_error(error, _bun_lock)
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

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def npmrc_content(bun_lock)
          NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files,
            dependencies: lockfile_dependencies(bun_lock)
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
