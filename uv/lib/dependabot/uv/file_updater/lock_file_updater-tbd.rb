# typed: strict
#  frozen_string_literal: true

require "toml-rb"
require "dependabot/file_updaters"
require "dependabot/uv/file_updater"
require "dependabot/shared_helpers"

module Dependabot
  module Uv
    class FileUpdater
      class LockFileupdater

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :credentials

        def initialize(dependencies:, dependency_files:, credentials:, index_urls: nil)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @index_urls = index_urls
        end

        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency
          dependencies.first
        end

        def fetch_updated_dependency_files

        end

        def generate_new_uv_lock_file
          SharedHelpers.in_a_temporary_directory do
            write_updated_dependency_files
            language_version_manager.install_required_python

            files_to_update.each do |filename|
              generate_file(filename)
            end

            # Remove any .python-version file before parsing the reqs
            FileUtils.remove_entry(".python-version", true)

            dependency_files.filter_map do |file|
              next unless file.name == "uv.lock"

              updated_content = File.read(file.name)
              next if updated_content == file.content

              file.dup.tap { |f| f.content = updated_content }
            end
          end
        end

        def write_updated_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, freeze_dependency_requirement(file))
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)
        end

        def files_to_update

        end

        def generate_file
          run_command(
            "pyenv local #{language_version_manager.python_major_minor}",
            fingerprint: "pyenv local <python_major_minor>"
          )

          run_command(
            "uv lock --upgrade-package #{dependency.name}",
            allow_unsafe_shell_command: allow_unsafe_shell_command,
            fingerprint: "uv lock --upgrade-package #{dependency.name}"
          )
        end

        def run_command(cmd, env: python_env, allow_unsafe_shell_command: false, fingerprint:)
          SharedHelpers.run_shell_command(
            cmd,
            env: env,
            allow_unsafe_shell_command: allow_unsafe_shell_command,
            fingerprint: fingerprint,
            stderr_to_stdout: true
          )
        end

        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end
      end
    end
  end
end
