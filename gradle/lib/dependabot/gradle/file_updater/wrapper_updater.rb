# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/distributions"

module Dependabot
  module Gradle
    class FileUpdater
      class WrapperUpdater
        extend T::Sig
        include Dependabot::Gradle::Distributions

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile], dependency: Dependabot::Dependency).void }
        def initialize(dependency_files:, dependency:)
          @dependency_files = dependency_files
          @dependency = dependency
          @target_files = T.let(
            %w(
              /gradlew
              /gradlew.bat
              /gradle/wrapper/gradle-wrapper.properties
              /gradle/wrapper/gradle-wrapper.jar
            ),
            T::Array[String]
          )
          @build_files = T.let(
            %w(
              build.gradle
              build.gradle.kts
              settings.gradle
              settings.gradle.kts
            ),
            T::Array[String]
          )
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def update_files(build_file)
          # We only run this updater if it's a distribution dependency
          return [] unless Distributions.distribution_requirements?(dependency.requirements)

          # Find all wrapper files - they can span multiple directories
          local_files = dependency_files.select { |file| target_file?(file) }

          # If we don't have any files in the build files don't generate one
          return dependency_files unless local_files.any?

          updated_files = dependency_files.dup
          SharedHelpers.in_a_temporary_directory do |temp_dir|
            populate_temp_directory(temp_dir)
            update_wrapper_files(build_file, temp_dir, local_files, updated_files)
          end
          updated_files
        end

        private

        sig do
          params(
            build_file: Dependabot::DependencyFile,
            temp_dir: T.any(Pathname, String),
            local_files: T::Array[Dependabot::DependencyFile],
            updated_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def update_wrapper_files(build_file, temp_dir, local_files, updated_files)
          cwd = File.join(temp_dir, base_path(build_file))

          # Create gradle.properties file with proxy settings
          properties_filename = File.join(temp_dir, build_file.directory, "gradle.properties")
          write_properties_file(properties_filename)

          Dir.chdir(cwd) do
            run_wrapper_tasks(cwd)
            update_file_contents(temp_dir, local_files, updated_files)
          rescue SharedHelpers::HelperSubprocessFailed => e
            handle_wrapper_update_error(e)
          end
        end

        sig { params(cwd: String).void }
        def run_wrapper_tasks(cwd)
          gradlew_script = File.exist?("gradlew.bat") && !File.exist?("gradlew") ? "gradlew.bat" : "./gradlew"

          # First run: Update wrapper with new version and download new distribution
          first_command = Shellwords.join([gradlew_script, "--no-daemon", "--stacktrace"] + command_args)
          SharedHelpers.run_shell_command(first_command, cwd: cwd)

          # Second run: Regenerate wrapper binaries (gradlew, gradlew.bat, gradle-wrapper.jar)
          second_command = Shellwords.join([gradlew_script, "--no-daemon", "--stacktrace", "wrapper"])
          SharedHelpers.run_shell_command(second_command, cwd: cwd)
        end

        sig do
          params(
            temp_dir: T.any(Pathname, String),
            local_files: T::Array[Dependabot::DependencyFile],
            updated_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def update_file_contents(temp_dir, local_files, updated_files)
          local_files.each do |file|
            file_path = File.join(temp_dir, file.directory, file.name)
            f_content = file.binary? ? File.binread(file_path) : File.read(file_path)
            tmp_file = file.dup
            tmp_file.content = file.binary? ? Base64.encode64(f_content) : f_content
            updated_files[T.must(updated_files.index(file))] = tmp_file
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def target_file?(file)
          @target_files.any? { |r| "/#{file.name}".end_with?(r) }
        end

        sig { returns(T::Array[String]) }
        def command_args
          version = T.let(dependency.requirements[0]&.[](:requirement), String)
          checksum = T.let(dependency.requirements[1]&.[](:requirement), String) if dependency.requirements.size > 1

          args = %W(wrapper --no-validate-url --gradle-version #{version})
          args += %W(--gradle-distribution-sha256-sum #{checksum}) if checksum
          args
        end

        # Gradle builds can be complex, to maximize the chances of a successful we just keep related wrapper files
        # and produce a minimal build for it to run (losing any customisations of the `wrapper` task in the process)
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def files_to_populate
          @dependency_files.filter_map do |f|
            next f if target_file?(f)
            next Dependabot::DependencyFile.new(directory: f.directory, name: f.name, content: "") if build_file?(f)
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def build_file?(file)
          @build_files.include?(File.basename(file.name))
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(String) }
        def base_path(build_file)
          File.dirname(File.join(build_file.directory, build_file.name)).delete_suffix("/gradle/wrapper")
        end

        sig { params(temp_dir: T.any(Pathname, String)).void }
        def populate_temp_directory(temp_dir)
          files_to_populate.each do |file|
            in_path_name = File.join(temp_dir, file.directory, file.name)
            FileUtils.mkdir_p(File.dirname(in_path_name))

            # Write file content - binary files need special handling
            if file.binary?
              File.binwrite(in_path_name, Base64.decode64(T.must(file.content)))
            else
              File.write(in_path_name, file.content)
            end

            # Make gradlew scripts executable so they can be run
            FileUtils.chmod(0o755, in_path_name) if file.name.end_with?("gradlew", "gradlew.bat")
          end
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.noreturn) }
        def handle_wrapper_update_error(error)
          # Gradle wrapper update failures typically indicate build compatibility issues
          # with the new Gradle version. Raise as DependencyFileNotResolvable so the
          # service layer can handle appropriately.
          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        sig { params(file_name: String).void }
        def write_properties_file(file_name) # rubocop:disable Metrics/PerceivedComplexity
          http_proxy = ENV.fetch("HTTP_PROXY", nil)
          https_proxy = ENV.fetch("HTTPS_PROXY", nil)
          http_split = http_proxy&.split(":")
          https_split = https_proxy&.split(":")
          http_proxy_host = http_split&.fetch(1, nil)&.gsub("//", "") || "host.docker.internal"
          https_proxy_host = https_split&.fetch(1, nil)&.gsub("//", "") || "host.docker.internal"
          http_proxy_port = http_split&.fetch(2) || "1080"
          https_proxy_port = https_split&.fetch(2) || "1080"
          properties_content = "
systemProp.http.proxyHost=#{http_proxy_host}
systemProp.http.proxyPort=#{http_proxy_port}
systemProp.https.proxyHost=#{https_proxy_host}
systemProp.https.proxyPort=#{https_proxy_port}"
          File.write(file_name, properties_content)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
