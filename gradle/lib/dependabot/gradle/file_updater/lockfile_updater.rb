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
            httpProxy = ENV["HTTP_PROXY"]
            httpsProxy = ENV["HTTPS_PROXY"]
            httpProxyHost = httpProxy ? httpProxy.split(":")[1].gsub("//", "") : "host.docker.internal"
            httpsProxyHost = httpsProxy ? httpsProxy.split(":")[1].gsub("//", "") : "host.docker.internal"
            httpProxyPort = httpProxy ? httpProxy.split(":")[2] : "1080"
            httpsProxyPort = httpsProxy ? httpsProxy.split(":")[2] : "1080"
            properties_content = "
systemProp.http.proxyHost=#{httpProxyHost}
systemProp.http.proxyPort=#{httpProxyPort}
systemProp.https.proxyHost=#{httpsProxyHost}
systemProp.https.proxyPort=#{httpsProxyPort}"
            File.write(properties_filename, properties_content)

            command_parts = [
              "gradle",
              "dependencies",
              "--no-daemon",
              "--write-locks",
              "--debug"
            ]
            command = Shellwords.join(command_parts)
            env = {
              "HTTP_PROXY" => httpProxy,
              "HTTPS_PROXY" => httpsProxy,
              "SOCKS_PROXY" => httpsProxy,
            }

            Dir.chdir(cwd) do
              stdout = SharedHelpers.run_shell_command(command, env: env, cwd: cwd)
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
      end
    end
  end
end
