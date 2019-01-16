# frozen_string_literal: true

require "toml-rb"
require "open3"
require "dependabot/git_commit_checker"
require "dependabot/cargo/file_updater"
require "dependabot/cargo/file_updater/manifest_updater"
require "dependabot/cargo/file_parser"
require "dependabot/shared_helpers"

module Dependabot
  module Cargo
    class FileUpdater
      class LockfileUpdater
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def updated_lockfile_content
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              # Shell out to Cargo, which handles everything for us, and does
              # so without doing an install (so it's fast).
              command = "cargo update -p #{dependency_spec}"
              run_shell_command(command)
            end

            updated_lockfile = File.read("Cargo.lock")
            updated_lockfile = post_process_lockfile(updated_lockfile)

            if updated_lockfile.include?(desired_lockfile_content)
              next updated_lockfile
            end

            raise "Failed to update #{dependency.name}!"
          end
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => error
          handle_cargo_error(error)
        end

        private

        attr_reader :dependencies, :dependency_files, :credentials

        # Currently, there will only be a single updated dependency
        def dependency
          dependencies.first
        end

        def handle_cargo_error(error)
          raise unless error.message.include?("failed to select a version") ||
                       error.message.include?("no matching version")
          raise if error.message.include?("`#{dependency.name} ")

          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        def dependency_spec
          spec = dependency.name

          if git_dependency?
            spec += ":#{git_previous_version}" if git_previous_version
          elsif dependency.previous_version
            spec += ":#{dependency.previous_version}"
          end

          spec
        end

        def git_previous_version
          TomlRB.parse(lockfile.content).
            fetch("package", []).
            select { |p| p["name"] == dependency.name }.
            find { |p| p["source"].end_with?(dependency.previous_version) }.
            fetch("version")
        end

        def desired_lockfile_content
          return dependency.version if git_dependency?

          %(name = "#{dependency.name}"\nversion = "#{dependency.version}")
        end

        def run_shell_command(command)
          start = Time.now
          stdout, process = Open3.capture2e(command)
          time_taken = start - Time.now

          # Raise an error with the output from the shell session if Cargo
          # returns a non-zero status
          return if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end

        def write_temporary_dependency_files
          write_temporary_manifest_files
          write_temporary_path_dependency_files

          File.write(lockfile.name, lockfile.content)
          File.write(toolchain.name, toolchain.content) if toolchain
        end

        def write_temporary_manifest_files
          manifest_files.each do |file|
            path = file.name
            dir = Pathname.new(path).dirname
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_manifest_content(file))

            FileUtils.mkdir_p(File.join(dir, "src"))
            File.write(File.join(dir, "src/lib.rs"), dummy_app_content)
            File.write(File.join(dir, "src/main.rs"), dummy_app_content)
          end
        end

        def write_temporary_path_dependency_files
          path_dependency_files.each do |file|
            path = file.name
            dir = Pathname.new(path).dirname
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_path_dependency_content(file))

            FileUtils.mkdir_p(File.join(dir, "src"))
            File.write(File.join(dir, "src/lib.rs"), dummy_app_content)
            File.write(File.join(dir, "src/main.rs"), dummy_app_content)
          end
        end

        def prepared_manifest_content(file)
          content = updated_manifest_content(file)
          content = pin_version(content) unless git_dependency?
          content = replace_ssh_urls(content)
          content = remove_binary_specifications(content)
          content
        end

        def prepared_path_dependency_content(file)
          content = file.content.dup
          content = replace_ssh_urls(content)
          content
        end

        def updated_manifest_content(file)
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: file
          ).updated_manifest_content
        end

        def pin_version(content)
          parsed_manifest = TomlRB.parse(content)

          Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
            next unless (req = parsed_manifest.dig(type, dependency.name))

            updated_req = "=#{dependency.version}"

            if req.is_a?(Hash)
              parsed_manifest[type][dependency.name]["version"] = updated_req
            else
              parsed_manifest[type][dependency.name] = updated_req
            end
          end

          TomlRB.dump(parsed_manifest)
        end

        def replace_ssh_urls(content)
          git_ssh_requirements_to_swap.each do |ssh_url, https_url|
            content = content.gsub(ssh_url, https_url)
          end
          content
        end

        def remove_binary_specifications(content)
          parsed_manifest = TomlRB.parse(content)
          parsed_manifest.delete("bin")
          TomlRB.dump(parsed_manifest)
        end

        def post_process_lockfile(content)
          git_ssh_requirements_to_swap.each do |ssh_url, https_url|
            content = content.gsub(https_url, ssh_url)
          end

          content
        end

        def git_ssh_requirements_to_swap
          return @git_ssh_requirements_to_swap if @git_ssh_requirements_to_swap

          @git_ssh_requirements_to_swap = {}

          [*manifest_files, *path_dependency_files].each do |manifest|
            parsed_manifest = TomlRB.parse(manifest.content)

            Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
              (parsed_manifest[type] || {}).each do |_, details|
                next unless details.is_a?(Hash)
                next unless details["git"]&.match?(%r{ssh://git@(.*?)/})

                @git_ssh_requirements_to_swap[details["git"]] =
                  details["git"].gsub(%r{ssh://git@(.*?)/}, 'https://\1/')
              end
            end
          end

          @git_ssh_requirements_to_swap
        end

        def dummy_app_content
          %{fn main() {\nprintln!("Hello, world!");\n}}
        end

        def git_dependency?
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end

        def manifest_files
          @manifest_files ||=
            dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }.
            reject(&:support_file?)
        end

        def path_dependency_files
          @path_dependency_files ||=
            dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }.
            select(&:support_file?)
        end

        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "Cargo.lock" }
        end

        def toolchain
          @toolchain ||=
            dependency_files.find { |f| f.name == "rust-toolchain" }
        end
      end
    end
  end
end
