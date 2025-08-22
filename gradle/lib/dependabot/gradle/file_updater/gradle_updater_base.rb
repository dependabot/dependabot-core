# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class GradleUpdaterBase
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { params(_file: Dependabot::DependencyFile).returns(T::Boolean) }
        def target_file?(_file)
          raise NotImplementedError
        end

        sig { returns(T::Array[String]) }
        def command_args
          raise NotImplementedError
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(String) }
        def base_path(build_file)
          File.dirname(File.join(build_file.directory, build_file.name))
        end

        sig { params(build_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::DependencyFile]) }
        def update_files(build_file)
          local_files = dependency_files.select do |file|
            file.directory == build_file.directory && target_file?(file)
          end

          # If we don't have any files in the build files don't generate one
          return dependency_files unless local_files.any?

          updated_files = dependency_files.dup
          SharedHelpers.in_a_temporary_directory do |temp_dir|
            populate_temp_directory(temp_dir)
            cwd = File.join(temp_dir, base_path(build_file))

            # Create gradle.properties file with proxy settings
            # Would prefer to use command line arguments, but they don't work.
            properties_filename = File.join(temp_dir, build_file.directory, "gradle.properties")
            write_properties_file(properties_filename)

            command_parts = %w(gradle --no-daemon --stacktrace) + command_args
            command = Shellwords.join(command_parts)

            Dir.chdir(cwd) do
              SharedHelpers.run_shell_command(command, cwd: cwd)
              update_files_content(temp_dir, local_files, updated_files)
            rescue SharedHelpers::HelperSubprocessFailed => e
              puts "Failed to update files: #{e.message}"
              return updated_files
            end
          end
          updated_files
        end

        private

        sig do
          params(
            temp_dir: T.any(Pathname, String),
            local_files: T::Array[Dependabot::DependencyFile],
            updated_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def update_files_content(temp_dir, local_files, updated_files)
          local_files.each do |file|
            f_content = File.read(File.join(temp_dir, file.directory, file.name))
            tmp_file = file.dup
            tmp_file.content = tmp_file.binary? ? Base64.encode64(f_content) : f_content
            updated_files[T.must(updated_files.index(file))] = tmp_file
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def files_to_populate
          @dependency_files
        end

        sig { params(temp_dir: T.any(Pathname, String)).void }
        def populate_temp_directory(temp_dir)
          files_to_populate.each do |file|
            in_path_name = File.join(temp_dir, file.directory, file.name)
            FileUtils.mkdir_p(File.dirname(in_path_name))
            File.write(in_path_name, file.content)
          end
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
      end
    end
  end
end
