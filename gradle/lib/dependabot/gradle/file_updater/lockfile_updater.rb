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
          return @dependency_files unless local_lockfiles.any?

          updated_lockfiles = @dependency_files.dup
          SharedHelpers.in_a_temporary_directory do |temp_dir|
            populate_temp_directory(temp_dir)
            cwd = File.join(temp_dir, build_file.directory, build_file.name)
            cwd = File.dirname(cwd)

            # Create gradle.properties file with proxy settings
            # Would prefer to use command line arguments, but they don't work.
            properties_filename = File.join(temp_dir, build_file.directory, "gradle.properties")
            write_properties_file(properties_filename)

            command_parts = [
              "gradle",
              "dependencies",
              "--no-daemon",
              "--write-locks",
              "--debug"
            ]
            command = Shellwords.join(command_parts)

            Dir.chdir(cwd) do
              SharedHelpers.run_shell_command(command, cwd: cwd)
              update_lockfiles_content(temp_dir, local_lockfiles, updated_lockfiles)
            rescue SharedHelpers::HelperSubprocessFailed => e
              puts "Failed to update lockfiles: #{e.message}"
              return updated_lockfiles
            end
          end
          updated_lockfiles
        end

        sig do
          params(
            temp_dir: T.any(Pathname, String),
            local_lockfiles: T::Array[Dependabot::DependencyFile],
            updated_lockfiles: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def update_lockfiles_content(temp_dir, local_lockfiles, updated_lockfiles)
          local_lockfiles.each do |file|
            f_content = File.read(File.join(temp_dir, file.directory, file.name))
            tmp_file = file.dup
            tmp_file.content = f_content
            updated_lockfiles[T.must(updated_lockfiles.index(file))] = tmp_file
          end
        end

        sig { params(temp_dir: T.any(Pathname, String)).void }
        def populate_temp_directory(temp_dir)
          @dependency_files.each do |file|
            in_path_name = File.join(temp_dir, file.directory, file.name)
            FileUtils.mkdir_p(File.dirname(in_path_name))
            File.write(in_path_name, file.content)
          end
        end

        sig { params(file_name: String).void }
        def write_properties_file(file_name)
          http_proxy = ENV.fetch("HTTP_PROXY")
          https_proxy = ENV.fetch("HTTPS_PROXY")
          http_split = http_proxy.split(":")
          https_split = https_proxy.split(":")
          http_proxy_host = http_split[1] ? http_split[1]&.gsub("//", "") : "host.docker.internal"
          https_proxy_host = https_split[1] ? https_split[1]&.gsub("//", "") : "host.docker.internal"
          http_proxy_port = http_split[2] || "1080"
          https_proxy_port = https_split[2] || "1080"
          properties_content = "
systemProp.http.proxy_host=#{http_proxy_host}
systemProp.http.proxy_port=#{http_proxy_port}
systemProp.https.proxy_host=#{https_proxy_host}
systemProp.https.proxy_port=#{https_proxy_port}"
          File.write(file_name, properties_content)
        end
      end
    end
  end
end
