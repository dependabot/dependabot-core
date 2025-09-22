# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/hex/file_updater"
require "dependabot/hex/file_updater/mixfile_updater"
require "dependabot/hex/file_updater/mixfile_sanitizer"
require "dependabot/hex/file_updater/mixfile_requirement_updater"
require "dependabot/hex/credential_helpers"
require "dependabot/hex/native_helpers"
require "dependabot/hex/version"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    class FileUpdater
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content = T.let(@updated_lockfile_content, T.nilable(String))
          @updated_lockfile_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files
              FileUtils.cp(elixir_helper_do_update_path, "do_update.exs")

              SharedHelpers.with_git_configured(credentials: credentials) do
                SharedHelpers.run_helper_subprocess(
                  env: mix_env,
                  command: "mix run #{elixir_helper_path}",
                  function: "get_updated_lockfile",
                  args: [Dir.pwd, dependency.name, CredentialHelpers.hex_credentials(credentials)]
                )
              end
            end

          post_process_lockfile(@updated_lockfile_content)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Dependency) }
        def dependency
          # For now, we'll only ever be updating a single dep for Elixir
          T.must(dependencies.first)
        end

        sig { params(content: String).returns(String) }
        def post_process_lockfile(content)
          lockfile_content = T.must(lockfile.content)
          return content unless lockfile_content.start_with?("%{\"")
          return content if content.start_with?("%{\"")

          # Substitute back old file beginning and ending
          content.sub(/\A%\{\n  "/, "%{\"").sub("},\n}", "}}")
        end

        sig { void }
        def write_temporary_dependency_files
          mixfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, mixfile_content_for_lockfile_generation(file))
          end

          File.write("mix.lock", T.must(lockfile.content))

          dependency_files.select(&:support_file).each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitize_mixfile(T.must(file.content)))
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def mixfile_content_for_lockfile_generation(file)
          content = updated_mixfile_content(file)
          content = lock_mixfile_dependency_versions(content, file.name)
          sanitize_mixfile(content)
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_mixfile_content(file)
          MixfileUpdater.new(
            dependencies: dependencies,
            mixfile: file
          ).updated_mixfile_content
        end

        sig { params(mixfile_content: String, filename: String).returns(String) }
        def lock_mixfile_dependency_versions(mixfile_content, filename)
          dependencies
            .reduce(mixfile_content.dup) do |content, dep|
              # Run on the updated mixfile content, so we're updating from the
              # updated requirements
              req_details = dep.requirements.find { |r| r[:file] == filename }

              next content unless req_details
              next content unless Hex::Version.correct?(dep.version)

              MixfileRequirementUpdater.new(
                dependency_name: dep.name,
                mixfile_content: content,
                previous_requirement: req_details.fetch(:requirement),
                updated_requirement: dep.version,
                insert_if_bare: true
              ).updated_content
            end
        end

        sig { params(content: String).returns(String) }
        def sanitize_mixfile(content)
          MixfileSanitizer.new(mixfile_content: content).sanitized_content
        end

        sig { returns(T::Hash[String, String]) }
        def mix_env
          {
            "MIX_EXS" => File.join(NativeHelpers.hex_helpers_dir, "mix.exs"),
            "MIX_QUIET" => "1"
          }
        end

        sig { returns(String) }
        def elixir_helper_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/run.exs")
        end

        sig { returns(String) }
        def elixir_helper_do_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/do_update.exs")
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def mixfiles
          dependency_files.select { |f| f.name.end_with?("mix.exs") }
        end

        sig { returns(Dependabot::DependencyFile) }
        def lockfile
          @lockfile ||= T.let(
            T.must(dependency_files.find { |f| f.name == "mix.lock" }),
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
