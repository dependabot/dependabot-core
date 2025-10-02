# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"
require "open3"
require "dependabot/git_commit_checker"
require "dependabot/cargo/file_updater"
require "dependabot/cargo/file_updater/manifest_updater"
require "dependabot/cargo/file_parser"
require "dependabot/cargo/helpers"
require "dependabot/shared_helpers"
module Dependabot
  module Cargo
    class FileUpdater
      # rubocop:disable Metrics/ClassLength
      class LockfileUpdater
        extend T::Sig

        LOCKFILE_ENTRY_REGEX = /
          \[\[package\]\]\n
          (?:(?!^\[(?:\[package|metadata)).)+
        /mx

        LOCKFILE_CHECKSUM_REGEX = /^"checksum .*$/

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = T.let(dependencies, T::Array[Dependabot::Dependency])
          @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @custom_specification = T.let(nil, T.nilable(String))
          @git_ssh_requirements_to_swap = T.let(nil, T.nilable(T::Hash[String, String]))
          @manifest_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @path_dependency_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @lockfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @toolchain = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @config = T.let(nil, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T.any(String, T.noreturn)) }
        def updated_lockfile_content
          base_directory = T.must(dependency_files.first).directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              # Shell out to Cargo, which handles everything for us, and does
              # so without doing an install (so it's fast).
              run_cargo_command("cargo update -p #{dependency_spec}", fingerprint: "cargo update -p <dependency_spec>")
            end

            updated_lockfile = File.read("Cargo.lock")
            updated_lockfile = post_process_lockfile(updated_lockfile)

            next updated_lockfile if updated_lockfile.include?(desired_lockfile_content)

            # If exact version match fails, accept any update
            if dependency_updated?(updated_lockfile, dependency)
              actual_version = extract_actual_version(updated_lockfile, dependency.name)
              if actual_version && actual_version != dependency.version
                Dependabot.logger.info(
                  "Cargo selected version #{actual_version} instead of #{dependency.version} for #{dependency.name} " \
                  "due to dependency constraints"
                )
              end
              next updated_lockfile
            end

            raise "Failed to update #{dependency.name}!"
          end
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          retry if better_specification_needed?(e)
          handle_cargo_error(e)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        # Currently, there will only be a single updated dependency
        sig { returns(Dependabot::Dependency) }
        def dependency
          T.must(dependencies.first)
        end

        sig { params(error: StandardError).returns(T.noreturn) }
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
        sig { params(error: StandardError).returns(T::Boolean) }
        def better_specification_needed?(error)
          return false if @custom_specification
          return false unless error.message.match?(/specification .* is ambigu/)

          spec_options = error.message.gsub(/.*following:\n/m, "")
                              .lines.map(&:strip)

          ver = if git_dependency? && git_previous_version
                  git_previous_version
                else
                  dependency.version
                end

          if ver && spec_options.one? { |s| s.end_with?(ver) }
            @custom_specification = spec_options.find { |s| s.end_with?(ver) }
            return true
          elsif ver && spec_options.count { |s| s.end_with?(ver) } > 1
            spec_options.select! { |s| s.end_with?(ver) }
          end

          if git_dependency? && git_source_url &&
             spec_options.count { |s| s.include?(T.must(git_source_url)) } >= 1
            spec_options.select! { |s| s.include?(T.must(git_source_url)) }
          end

          @custom_specification = spec_options.first
          true
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(String) }
        def dependency_spec
          return @custom_specification if @custom_specification

          spec = dependency.name

          if git_dependency?
            spec += ":#{git_previous_version}" if git_previous_version
          elsif dependency.previous_version
            spec += ":#{dependency.previous_version}"
          end

          spec
        end

        sig { returns(T.nilable(String)) }
        def git_previous_version
          TomlRB.parse(lockfile.content)
                .fetch("package", [])
                .select { |p| p["name"] == dependency.name }
                .find { |p| p["source"].end_with?(dependency.previous_version) }
                &.fetch("version")
        end

        sig { returns(T.nilable(String)) }
        def git_source_url
          dependency.previous_requirements
                    &.find { |r| r.dig(:source, :type) == "git" }
                    &.dig(:source, :url)
        end

        sig { returns(String) }
        def desired_lockfile_content
          return T.must(dependency.version) if git_dependency?

          %(name = "#{dependency.name}"\nversion = "#{dependency.version}")
        end

        sig { params(command: String, fingerprint: String).void }
        def run_cargo_command(command, fingerprint:)
          start = Time.now

          # Check if any manifest file is a virtual workspace (has [workspace] with members but no [package])
          # Virtual workspaces are not supported as they complicate dependency resolution
          virtual_workspace = detect_virtual_workspace

          if virtual_workspace
            error_msg = "Dependabot does not currently support Cargo virtual workspaces"
            Dependabot.logger.error(error_msg)
            raise Dependabot::DependencyFileNotResolvable, error_msg
          end

          command = SharedHelpers.escape_command(command)
          Helpers.setup_credentials_in_environment(credentials)
          # Pass through any registry tokens supplied via CARGO_REGISTRIES_...
          # environment variables.
          env = ENV.select { |key, _value| key.match(/^CARGO_REGISTRIES_/) }
          stdout, process = Open3.capture2e(env, command)
          time_taken = Time.now - start

          # Raise an error with the output from the shell session if Cargo
          # returns a non-zero status
          return if process.success?

          if using_old_toolchain?(stdout)
            raise Dependabot::DependencyFileNotEvaluatable, "Dependabot only supports toolchain 1.68 and up."
          end

          # ambiguous package specification
          if (match = stdout.match(/There are multiple `([^`]+)` packages in your project, and the specification `([^`]+)` is ambiguous\./))
            raise Dependabot::DependencyFileNotEvaluatable, "Ambiguous package specification: #{match[2]}"
          end

          # package doesn't exist in the index
          if (match = stdout.match(/no matching package named `([^`]+)` found/))
            raise Dependabot::DependencyFileNotResolvable, match[1]
          end

          if (match = /error: no matching package found\nsearched package name: `([^`]+)`/m.match(stdout))
            raise Dependabot::DependencyFileNotResolvable, match[1]
          end

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

        sig { params(message: String).returns(T::Boolean) }
        def using_old_toolchain?(message)
          return true if message.include?("usage of sparse registries requires `-Z sparse-registry`")

          version_log = /rust version (?<version>\d.\d+)/.match(message)
          return false unless version_log

          version_class.new(version_log[:version]) < version_class.new("1.68")
        end

        sig { void }
        def write_temporary_dependency_files
          write_temporary_manifest_files
          write_temporary_path_dependency_files

          File.write(lockfile.name, lockfile.content)
          File.write(T.must(toolchain).name, T.must(toolchain).content) if toolchain
          return unless config

          FileUtils.mkdir_p(File.dirname(T.must(config).name))
          File.write(T.must(config).name, T.must(config).content)
        end

        sig { void }
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

        sig { void }
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

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def prepared_manifest_content(file)
          content = updated_manifest_content(file)
          content = pin_version(content) unless git_dependency?
          content = replace_ssh_urls(content)
          content = remove_binary_specifications(content)
          content = remove_default_run_specification(content)
          content
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def prepared_path_dependency_content(file)
          content = T.must(file.content).dup
          content = replace_ssh_urls(content)
          content
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_manifest_content(file)
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: file
          ).updated_manifest_content
        end

        sig { params(content: String).returns(String) }
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

        sig { params(parsed_manifest: T::Hash[String, T.untyped]).void }
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

        sig { params(content: String).returns(String) }
        def replace_ssh_urls(content)
          git_ssh_requirements_to_swap.each do |ssh_url, https_url|
            content = content.gsub(ssh_url, https_url)
          end
          content
        end

        sig { params(content: String).returns(String) }
        def remove_binary_specifications(content)
          parsed_manifest = TomlRB.parse(content)
          parsed_manifest.delete("bin")
          TomlRB.dump(parsed_manifest)
        end

        sig { params(content: String).returns(String) }
        def remove_default_run_specification(content)
          parsed_manifest = TomlRB.parse(content)
          parsed_manifest["package"].delete("default-run") if parsed_manifest.dig("package", "default-run")
          TomlRB.dump(parsed_manifest)
        end

        sig { params(content: String).returns(String) }
        def post_process_lockfile(content)
          git_ssh_requirements_to_swap.each do |ssh_url, https_url|
            content = content.gsub(https_url, ssh_url)
            content = remove_duplicate_lockfile_entries(content)
          end

          content
        end

        sig { returns(T::Hash[String, String]) }
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

        sig { params(lockfile_content: String).returns(String) }
        def remove_duplicate_lockfile_entries(lockfile_content)
          # Loop through the lockfile entries looking for duplicates. Replace
          # any that are found
          lockfile_entries = []
          lockfile_content.scan(LOCKFILE_ENTRY_REGEX) do
            lockfile_entries << Regexp.last_match.to_s
          end
          lockfile_entries
            .select { |e| lockfile_entries.count(e) > 1 }.uniq
            .each do |entry|
              (lockfile_entries.count(entry) - 1)
                .times { lockfile_content = lockfile_content.sub(entry, "") }
            end

          # Loop through the lockfile checksums looking for duplicates. Replace
          # any that are found
          lockfile_checksums = []
          lockfile_content.scan(LOCKFILE_CHECKSUM_REGEX) do
            lockfile_checksums << Regexp.last_match.to_s
          end
          lockfile_checksums
            .select { |e| lockfile_checksums.count(e) > 1 }.uniq
            .each do |cs|
              (lockfile_checksums.count(cs) - 1)
                .times { lockfile_content = lockfile_content.sub("\n#{cs}", "") }
            end

          lockfile_content
        end

        sig { returns(String) }
        def dummy_app_content
          %{fn main() {\nprintln!("Hello, world!");\n}}
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def manifest_files
          @manifest_files ||=
            dependency_files
            .select { |f| f.name.end_with?("Cargo.toml") }
            .reject(&:support_file?)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def path_dependency_files
          @path_dependency_files ||=
            dependency_files
            .select { |f| f.name.end_with?("Cargo.toml") }
            .select(&:support_file?)
        end

        sig { returns(Dependabot::DependencyFile) }
        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "Cargo.lock" }
          T.must(@lockfile)
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def toolchain
          @toolchain ||=
            dependency_files.find { |f| f.name == "rust-toolchain" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def config
          @config ||= dependency_files.find { |f| f.name == ".cargo/config.toml" }
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def virtual_manifest?(file)
          !T.must(file.content).include?("[package]")
        end

        sig { returns(T.class_of(Gem::Version)) }
        def version_class
          dependency.version_class
        end

        sig { params(lockfile_content: String, dependency: Dependabot::Dependency).returns(T::Boolean) }
        def dependency_updated?(lockfile_content, dependency)
          return false unless dependency.previous_version

          # For multiple versions case, we need to check the specific entry
          # that corresponds to our dependency (the one used by our package)
          entries = T.let([], T::Array[String])
          lockfile_content.scan(LOCKFILE_ENTRY_REGEX) do
            entries << Regexp.last_match.to_s
          end
          entries.select! { |entry| entry.include?("name = \"#{dependency.name}\"") }

          # Check if any entry has a version newer than the previous version
          entries.any? do |entry|
            version_match = entry.match(/version = "([^"]+)"/)
            next false unless version_match

            new_version = version_match[1]
            # Only consider it updated if it's newer than the previous version
            # and either matches our expected version or is at least newer than previous
            dependency.version_class.new(new_version) > dependency.version_class.new(dependency.previous_version)
          end
        end

        sig { params(lockfile_content: String, dependency_name: String).returns(T.nilable(String)) }
        def extract_actual_version(lockfile_content, dependency_name)
          entries = T.let([], T::Array[String])
          lockfile_content.scan(LOCKFILE_ENTRY_REGEX) do
            entries << Regexp.last_match.to_s
          end
          entries.select! { |entry| entry.include?("name = \"#{dependency_name}\"") }

          # Get the highest version from matching entries
          versions = entries.filter_map do |entry|
            version_match = entry.match(/version = "([^"]+)"/)
            version_match&.captures&.first
          end

          return nil if versions.empty?

          versions.max_by { |v| version_class.new(v) }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def detect_virtual_workspace
          manifest_files.find { |file| virtual_workspace?(file) }
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def virtual_workspace?(file)
          return false unless file.content

          parsed_manifest = TomlRB.parse(file.content)
          # A virtual workspace has [workspace] with members but no [package]
          # Regular workspaces and workspace.dependencies are fine
          parsed_manifest.key?("workspace") &&
            parsed_manifest.dig("workspace", "members")&.any? &&
            !parsed_manifest.key?("package")
        rescue TomlRB::ParseError
          false
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
