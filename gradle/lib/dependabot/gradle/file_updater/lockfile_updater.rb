# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class LockfileUpdater
      extend T::Sig

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).void
      end
      def initialize(dependency_files:)
        @dependency_files = dependency_files
        @lock_files = T.let(dependency_files.select { |f| f.name.end_with?(".lockfile") }, T::Array[Dependabot::DependencyFile])
      end

      sig do
        params(build_file: Dependabot::DependencyFile)
        .returns(T::Array[Dependabot::DependencyFile])
      end
      def update_lockfiles(build_file)
        base_dir = build_file.directory
        # If we don't have any lockfiles in the build files don't generate one
        [] unless @dependency_files.any? do |file|
          file.directory == build_file.directory and file.name.end_with?(".lockfile")
        end

        updated_lockfiles = T.let(Array.new, T::Array[Dependabot::DependencyFile])
        SharedHelpers.in_a_temporary_directory do |temp_dir|
          for file in @dependency_files
            FileUtils.mkdir_p(Pathname.new(file.name).dirname)
            File.write(file.name, file.content)
          end

          command_parts = [
            "gradle",
            "build",
            "--write-locks"
          ]

          command = Shellwords.join(command_parts)
          begin
            output = SharedHelpers.run_shell_command(command, cwd: File.join(temp_dir, build_file.directory))
            for file in @lock_files.select{ |f| f.directory == build_file.directory }
              f_content = File.read(File.join(temp_dir, file.name))
              tmp_file = file.dup
              tmp_file.content = f_content
              updated_lockfiles << tmp_file
            end
          rescue SharedHelpers::HelperSubprocessFailed => e
            return updated_lockfiles
          end
        end

        return updated_lockfiles
      end
    end
  end
end
