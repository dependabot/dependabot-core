# frozen_string_literal: true

require "dependabot/nuget/file_updater"

module Dependabot
  module Nuget
    class FileUpdater
      class LockfileUpdater
        def initialize(dependency_files:, lock_file:, credentials:)
          @dependency_files = dependency_files
          @lock_file = lock_file
          @credentials = credentials
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              build_updated_lockfile
            end
        end

        private

        attr_reader :dependency_files, :lock_file, :credentials

        def build_updated_lockfile
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              dependency_files.each do |file|
                path = file.name
                FileUtils.mkdir_p(Pathname.new(path).dirname)
                File.write(path, file.content)
              end

              Dir.chdir(lock_file_directory) do
                run_dotnet_restore
              end
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_dotnet_restore_error(e)
        end

        def run_dotnet_restore
          command = [
            "dotnet",
            "restore",
            "--force-evaluate"
          ].join(" ")
          SharedHelpers.run_shell_command(command)

          File.read(lock_file_basename)
        end

        def handle_dotnet_restore_error(error)
          raise error
        end

        def lock_file_directory
          Pathname.new(lock_file.name).dirname.to_s
        end

        def lock_file_basename
          Pathname.new(lock_file.name).basename.to_s
        end
      end
    end
  end
end
