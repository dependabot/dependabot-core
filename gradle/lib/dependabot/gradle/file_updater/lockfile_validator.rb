# typed: strong
# frozen_string_literal: true

require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class LockfileValidator < LockfileUpdater
        extend T::Sig

        sig { params(build_file: Dependabot::DependencyFile, validation_script: String).void }
        def validate_lockfiles(build_file, validation_script:)
          root_dir = determine_root_dir(build_file: build_file)

          SharedHelpers.in_a_temporary_directory do |temp_dir|
            populate_temp_directory(temp_dir)
            cwd = File.join(temp_dir, root_dir.delete_prefix("/"))
            FileUtils.mkdir_p(cwd)

            init_script_path = File.join(cwd, "dependabot-locking-validation.init.gradle")
            File.write(init_script_path, validation_script)
            command = Shellwords.join(
              [
                gradle_executable_for(cwd: cwd, workspace_root: temp_dir.to_s),
                "--init-script", init_script_path,
                INIT_SCRIPT_TASK_NAME, "--no-daemon"
              ]
            )
            run_lockfile_update_with_retry(
              command: command, cwd: cwd, properties_file_path: File.join(cwd, "gradle.properties")
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotResolvable, "Gradle could not resolve the updated lockfile: #{e.message}"
        end
      end
    end
  end
end
