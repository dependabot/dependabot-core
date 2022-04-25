# frozen_string_literal: true

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
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def updated_lockfile_content
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

        attr_reader :dependencies, :dependency_files, :credentials

        def dependency
          # For now, we'll only ever be updating a single dep for Elixir
          dependencies.first
        end

        def post_process_lockfile(content)
          return content unless lockfile.content.start_with?("%{\"")
          return content if content.start_with?("%{\"")

          # Substitute back old file beginning and ending
          content.sub(/\A%\{\n  "/, "%{\"").sub(/\},\n\}/, "}}")
        end

        def write_temporary_dependency_files
          mixfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, mixfile_content_for_lockfile_generation(file))
          end

          File.write("mix.lock", lockfile.content)

          dependency_files.select(&:support_file).each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitize_mixfile(file.content))
          end
        end

        def mixfile_content_for_lockfile_generation(file)
          content = updated_mixfile_content(file)
          content = lock_mixfile_dependency_versions(content, file.name)
          sanitize_mixfile(content)
        end

        def updated_mixfile_content(file)
          MixfileUpdater.new(
            dependencies: dependencies,
            mixfile: file
          ).updated_mixfile_content
        end

        def lock_mixfile_dependency_versions(mixfile_content, filename)
          dependencies.
            reduce(mixfile_content.dup) do |content, dep|
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

        def sanitize_mixfile(content)
          MixfileSanitizer.new(mixfile_content: content).sanitized_content
        end

        def mix_env
          {
            "MIX_EXS" => File.join(NativeHelpers.hex_helpers_dir, "mix.exs"),
            "MIX_LOCK" => File.join(NativeHelpers.hex_helpers_dir, "mix.lock"),
            "MIX_DEPS" => File.join(NativeHelpers.hex_helpers_dir, "deps"),
            "MIX_QUIET" => "1"
          }
        end

        def elixir_helper_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/run.exs")
        end

        def elixir_helper_do_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/do_update.exs")
        end

        def mixfiles
          dependency_files.select { |f| f.name.end_with?("mix.exs") }
        end

        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "mix.lock" }
        end
      end
    end
  end
end
