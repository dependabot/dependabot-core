# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig do
          params(build_file: Dependabot::DependencyFile)
            .returns(T::Array[Dependabot::DependencyFile])
        end
        def update_lockfiles(build_file)
          local_lockfiles = @dependency_files.select do |file|
            file.directory == build_file.directory && file.name.end_with?(".lockfile")
          end
          # If we don't have any lockfiles in the build files don't generate one
          return [] unless local_lockfiles.any?

          updated_lockfiles = T.let([], T::Array[Dependabot::DependencyFile])
          SharedHelpers.in_a_temporary_directory do |temp_dir|
            @dependency_files.each do |file|
              FileUtils.mkdir_p(Pathname.new(file.name).dirname)
              File.write(file.name, file.content)
            end

            command_parts = ["gradle", "dependencies", "--write-locks"]

            command = Shellwords.join(command_parts)
            begin
              SharedHelpers.run_shell_command(command, cwd: File.join(temp_dir, build_file.directory))
              local_lockfiles.each do |file|
                f_content = File.read(File.join(temp_dir, file.name))
                tmp_file = file.dup
                tmp_file.content = f_content
                updated_lockfiles << tmp_file
              end
            rescue SharedHelpers::HelperSubprocessFailed
              return updated_lockfiles
            end
          end

          updated_lockfiles
        end
      end
    end
  end
end
