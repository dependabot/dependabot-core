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
        LOCKFILE_ENTRY_REGEX = /
          \[\[package\]\]\n
          (?:(?!^\[(\[package|metadata)).)+
        /mx

        LOCKFILE_CHECKSUM_REGEX = /^"checksum .*$/

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
              run_shell_command("cargo update -p #{dependency_spec}", fingerprint: "cargo update -p <dependency_spec>")
            end

            updated_lockfile = File.read("Cargo.lock")
            updated_lockfile = post_process_lockfile(updated_lockfile)

            next updated_lockfile if updated_lockfile.include?(desired_lockfile_content)

            raise "Failed to update #{dependency.name}!"
          end
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          retry if better_specification_needed?(e)
          handle_cargo_error(e)
        end

        private

        attr_reader :dependencies, :dependency_files, :credentials

        # Currently, there will only be a single updated dependency
        def dependency
          dependencies.first
        end

        def handle_cargo_error(error)
          raise unless error.message.include?("failed to select a version") ||
                       error.message.include?("no matching version") ||
                       error.message.include?("unexpected end of input while parsing major version number")
          raise if error.message.include?("`#{dependency.name} ")

          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/AbcSize
        def better_specification_needed?(error)
          return false if @custom_specification
          return false unless error.message.match?(/specification .* is ambigu/)

          spec_options = error.message.gsub(/.*following:\n/m, "").
                         lines.map(&:strip)

          ver = if git_dependency? && git_previous_version
                  git_previous_version
                else
                  dependency.version
                end

          if spec_options.count { |s| s.end_with?(ver) } == 1
            @custom_specification = spec_options.find { |s| s.end_with?(ver) }
            return true
          elsif spec_options.count { |s| s.end_with?(ver) } > 1
            spec_options.select! { |s| s.end_with?(ver) }
          end

          if git_dependency? && git_source_url &&
             spec_options.count { |s| s.include?(git_source_url) } >= 1
            spec_options.select! { |s| s.include?(git_source_url) }
          end

          @custom_specification = spec_options.first
          true
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def dependency_spec
          return @custom_specification if @custom_specification

          spec = dependency.name

          if git_dependency?
            spec += ":#{git_previous_version}" if git_previous_version
          elsif dependency.previous_version
            spec += ":#{dependency.previous_version}"
            spec = "https://github.com/rust-lang/crates.io-index#" + spec
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

        def git_source_url
          dependency.previous_requirements.
            find { |r| r.dig(:source, :type) == "git" }&.
            dig(:source, :url)
        end

        def desired_lockfile_content
          return dependency.version if git_dependency?

          %(name = "#{dependency.name}"\nversion = "#{dependency.version}")
        end

        def run_shell_command(command, fingerprint:)
          start = Time.now
          command = SharedHelpers.escape_command(command)
          stdout, process = Open3.capture2e(command)
          time_taken = Time.now - start

          # Raise an error with the output from the shell session if Cargo
          # returns a non-zero status
          return if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              fingerprint: fingerprint,
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

            next if virtual_manifest?(file)

            File.write(File.join(dir, "build.rs"), dummy_app_content)

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
          content = remove_default_run_specification(content)
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

          pin_target_specific_dependencies!(parsed_manifest)

          TomlRB.dump(parsed_manifest)
        end

        def pin_target_specific_dependencies!(parsed_manifest)
          parsed_manifest.fetch("target", {}).each do |target, t_details|
            Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
              t_details.fetch(type, {}).each do |name, requirement|
                next unless name == dependency.name

                updated_req = "=#{dependency.version}"

                if requirement.is_a?(Hash)
                  parsed_manifest["target"][target][type][name]["version"] =
                    updated_req
                else
                  parsed_manifest["target"][target][type][name] = updated_req
                end
              end
            end
          end
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

        def remove_default_run_specification(content)
          parsed_manifest = TomlRB.parse(content)
          parsed_manifest["package"].delete("default-run") if parsed_manifest.dig("package", "default-run")
          TomlRB.dump(parsed_manifest)
        end

        def post_process_lockfile(content)
          git_ssh_requirements_to_swap.each do |ssh_url, https_url|
            content = content.gsub(https_url, ssh_url)
            content = remove_duplicate_lockfile_entries(content)
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

        def remove_duplicate_lockfile_entries(lockfile_content)
          # Loop through the lockfile entries looking for duplicates. Replace
          # any that are found
          lockfile_entries = []
          lockfile_content.scan(LOCKFILE_ENTRY_REGEX) do
            lockfile_entries << Regexp.last_match.to_s
          end
          lockfile_entries.
            select { |e| lockfile_entries.count(e) > 1 }.uniq.
            each do |entry|
              (lockfile_entries.count(entry) - 1).
                times { lockfile_content = lockfile_content.sub(entry, "") }
            end

          # Loop through the lockfile checksums looking for duplicates. Replace
          # any that are found
          lockfile_checksums = []
          lockfile_content.scan(LOCKFILE_CHECKSUM_REGEX) do
            lockfile_checksums << Regexp.last_match.to_s
          end
          lockfile_checksums.
            select { |e| lockfile_checksums.count(e) > 1 }.uniq.
            each do |cs|
              (lockfile_checksums.count(cs) - 1).
                times { lockfile_content = lockfile_content.sub("\n#{cs}", "") }
            end

          lockfile_content
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

        def virtual_manifest?(file)
          !file.content.include?("[package]")
        end
      end
    end
  end
end
