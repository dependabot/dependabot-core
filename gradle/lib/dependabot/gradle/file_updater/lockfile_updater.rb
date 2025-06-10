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
            @dependency_files.each do |file|
              in_path_name = File.join(temp_dir, file.directory, file.name)
              FileUtils.mkdir_p(File.dirname(in_path_name))
              puts "#{in_path_name} => #{file.content}"
              File.write(in_path_name, file.content)
            end
            cwd = File.join(temp_dir, build_file.directory, build_file.name)
            cwd = File.dirname(cwd)

            # Create gradle.properties file with proxy settings if needed
            # This is needed for Gradle to resolve dependencies without network issues
            # when running in a Docker container behind a proxy
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
              SharedHelpers.run_shell_command(command, env: env, cwd: cwd)
              local_lockfiles.each do |file|
                f_content = File.read(File.join(temp_dir, file.directory, file.name))
                tmp_file = file.dup
                tmp_file.content = f_content
                updated_lockfiles[T.must(updated_lockfiles.index(file))] = tmp_file
              end
            rescue SharedHelpers::HelperSubprocessFailed => e
              puts "Failed to update lockfiles: #{e.message}"
              return updated_lockfiles
            end
          end
          updated_lockfiles
        end

        sig { params(file_name: String).void }
        def write_properties_file(file_name)
          http_proxy = ENV["HTTP_PROXY"]
          https_proxy = ENV["HTTPS_PROXY"]
          http_proxy_host = http_proxy ? T.must(http_proxy.split(":")[1]).gsub("//", "") : "host.docker.internal"
          https_proxy_host = https_proxy ? T.must(https_proxy.split(":")[1]).gsub("//", "") : "host.docker.internal"
          http_proxy_port = http_proxy ? http_proxy.split(":")[2] : "1080"
          https_proxy_port = https_proxy ? https_proxy.split(":")[2] : "1080"
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
