# typed: strong
# frozen_string_literal: true

require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class LockfileValidator < LockfileUpdater
        extend T::Sig

        sig { override.params(build_file: Dependabot::DependencyFile).returns(String) }
        def determine_root_dir(build_file:)
          root = super
          build_src_root = normalized_directory_path(build_file)[%r{\A(.*/buildSrc)(?:/|\z)}, 1]
          return root unless build_src_root && build_src_root.length > root.length

          build_src_root
        end

        sig { params(build_file: Dependabot::DependencyFile, validation_script: String).void }
        def validate_lockfiles(build_file, validation_script:)
          root_dir = determine_root_dir(build_file: build_file)

          SharedHelpers.in_a_temporary_directory do |temp_dir|
            populate_temp_directory(temp_dir)
            cwd = File.join(temp_dir, root_dir.delete_prefix("/"))
            FileUtils.mkdir_p(cwd)
            if File.basename(root_dir) == "buildSrc" &&
               %w(settings.gradle settings.gradle.kts).none? { |name| File.exist?(File.join(cwd, name)) }
              File.write(File.join(cwd, "settings.gradle"), "")
            end

            init_script_path = File.join(cwd, "dependabot-locking-validation.init.gradle")
            File.write(
              init_script_path,
              "gradle.projectsEvaluated {\n#{compiler_fallback_snippet}\n}\n#{validation_script}"
            )
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
