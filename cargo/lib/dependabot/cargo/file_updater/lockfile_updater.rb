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
          @custom_specifications = T.let({}, T::Hash[String, String])
          @current_dependency = T.let(nil, T.nilable(Dependabot::Dependency))
          @git_ssh_requirements_to_swap = T.let(nil, T.nilable(T::Hash[String, String]))
          @manifest_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @path_dependency_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @lockfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @toolchain = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @config_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
        end

        sig { returns(T.any(String, T.noreturn)) }
        def updated_lockfile_content
          base_directory = T.must(dependency_files.first).directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files
            run_updates

            updated_lockfile = File.read("Cargo.lock")
            updated_lockfile = post_process_lockfile(updated_lockfile)
            validate_updates(updated_lockfile)
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

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Dependency) }
        def dependency
          @current_dependency || T.must(dependencies.first)
        end

        sig { void }
        def run_updates
          SharedHelpers.with_git_configured(credentials: credentials) do
            # Shell out to Cargo, which handles everything for us, and does
            # so without doing an install (so it's fast).
            dependencies.each do |dependency_to_update|
              @current_dependency = dependency_to_update
              run_cargo_command(
                "cargo update -p #{dependency_spec}",
                fingerprint: "cargo update -p <dependency_spec>"
              )
            end
          end
        end

        sig { params(updated_lockfile: String).returns(String) }
        def validate_updates(updated_lockfile)
          dependencies.each do |updated_dependency|
            @current_dependency = updated_dependency
            validate_dependency_update(updated_lockfile)
          end

          updated_lockfile
        end

        sig { params(updated_lockfile: String).void }
        def validate_dependency_update(updated_lockfile)
          raise "Failed to update #{dependency.name}!" unless previous_package_replaced?(updated_lockfile, dependency)

          return if updated_lockfile.include?(desired_lockfile_content)

          raise "Failed to update #{dependency.name}!" unless dependency_updated?(updated_lockfile, dependency)

          actual_version = extract_actual_version(updated_lockfile, dependency)
          return unless actual_version && actual_version != dependency.version

          Dependabot.logger.info(
            "Cargo selected version #{actual_version} instead of #{dependency.version} " \
            "for #{dependency.name} due to dependency constraints"
          )
        end

        sig { params(error: StandardError).returns(T.noreturn) }
        def handle_cargo_error(error)
          raise unless resolvable_cargo_error?(error.message)
          raise if error.message.include?("`#{dependency.name} ")

          extract_binary_path_error(error.message)
        end

        sig { params(message: String).returns(T::Boolean) }
        def resolvable_cargo_error?(message)
          message.include?("failed to select a version") ||
            message.include?("no matching version") ||
            message.include?("unexpected end of input while parsing major version number") ||
            message.match?(/couldn't find `[^`]+\.rs`/) ||
            message.match?(/failed to find `[^`]+\.rs`/) ||
            message.match?(/could not find `[^`]+\.rs`/) ||
            message.match?(/cannot find binary `[^`]+`/) ||
            message.include?("Please specify bin.path if you want to use a non-default path") ||
            message.include?("binary target")
        end

        sig { params(message: String).returns(T.noreturn) }
        def extract_binary_path_error(message)
          if (match = message.match(/can't find `([^`]+)` bin at `([^`]+)`/))
            binary_name = match[1]
            expected_path = match[2]
            raise Dependabot::DependencyFileNotResolvable,
                  "Binary '#{binary_name}' not found at expected path '#{expected_path}'. " \
                  "Please check the bin.path configuration in Cargo.toml."
          elsif (match = message.match(/(couldn't find|failed to find|could not find) `([^`]+\.rs)`/))
            file_path = match[2]
            raise Dependabot::DependencyFileNotResolvable,
                  "Source file '#{file_path}' not found. Please check the bin.path configuration in Cargo.toml."
          elsif (match = message.match(/cannot find binary `([^`]+)`/))
            binary_name = match[1]
            raise Dependabot::DependencyFileNotResolvable,
                  "Binary target '#{binary_name}' not found. Please check the [[bin]] configuration in Cargo.toml."
          end

          raise Dependabot::DependencyFileNotResolvable, message
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/AbcSize
        sig { params(error: StandardError).returns(T::Boolean) }
        def better_specification_needed?(error)
          return false if custom_specification
          return false unless error.message.match?(/specification .* is ambigu/)

          spec_options = error.message.gsub(/.*following:\n/m, "")
                              .lines.map(&:strip)

          ver = if git_dependency? && git_previous_version
                  git_previous_version
                else
                  dependency.version
                end

          if ver && spec_options.one? { |s| s.end_with?(ver) }
            @custom_specifications[dependency_identity] = T.must(spec_options.find { |s| s.end_with?(ver) })
            return true
          elsif ver && spec_options.count { |s| s.end_with?(ver) } > 1
            spec_options.select! { |s| s.end_with?(ver) }
          end

          if git_dependency? && git_source_url &&
             spec_options.count { |s| s.include?(T.must(git_source_url)) } >= 1
            spec_options.select! { |s| s.include?(T.must(git_source_url)) }
          end

          @custom_specifications[dependency_identity] = T.must(spec_options.first)
          true
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(String) }
        def dependency_spec
          return T.must(custom_specification) if custom_specification

          spec = dependency.name

          if git_dependency?
            spec += ":#{git_previous_version}" if git_previous_version
          elsif dependency.previous_version
            spec += ":#{dependency.previous_version}"
          end

          spec
        end

        sig { returns(T.nilable(String)) }
        def custom_specification
          @custom_specifications[dependency_identity]
        end

        sig { returns(String) }
        def dependency_identity
          [
            dependency.name,
            dependency.previous_version,
            dependency.version,
            dependency.metadata[:cargo_package_source]
          ].join("\0")
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
          command = SharedHelpers.escape_command(command)
          env = Helpers.cargo_command_env(dependency_files, credentials)
          stdout, process = Open3.capture2e(env, command)
          time_taken = Time.now - start

          return if process.success?

          handle_cargo_command_error(stdout, command, fingerprint, time_taken)
        end

        sig { params(stdout: String, command: String, fingerprint: String, time_taken: Float).returns(T.noreturn) }
        def handle_cargo_command_error(stdout, command, fingerprint, time_taken)
          if using_old_toolchain?(stdout)
            raise Dependabot::DependencyFileNotEvaluatable, "Dependabot only supports toolchain 1.68 and up."
          end

          check_ambiguous_package_error(stdout)
          check_missing_package_error(stdout)
          check_binary_path_error(stdout)

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              fingerprint: fingerprint,
              time_taken: time_taken,
              process_exit_value: "non-zero"
            }
          )
        end

        sig { params(stdout: String).void }
        def check_ambiguous_package_error(stdout)
          ambiguous_match = stdout.match(/There are multiple `([^`]+)` packages.*specification `([^`]+)` is ambiguous/)
          return unless ambiguous_match

          raise Dependabot::DependencyFileNotEvaluatable, "Ambiguous package specification: #{ambiguous_match[2]}"
        end

        sig { params(stdout: String).void }
        def check_missing_package_error(stdout)
          if (match = stdout.match(/no matching package named `([^`]+)` found/))
            raise Dependabot::DependencyFileNotResolvable, match[1]
          end

          if (match = /error: no matching package found\nsearched package name: `([^`]+)`/m.match(stdout))
            raise Dependabot::DependencyFileNotResolvable, match[1]
          end
        end

        sig { params(stdout: String).void }
        def check_binary_path_error(stdout)
          return unless binary_path_error?(stdout)

          extract_binary_path_error(stdout)
        end

        sig { params(stdout: String).returns(T::Boolean) }
        def binary_path_error?(stdout)
          stdout.match?(/couldn't find `[^`]+\.rs`/) ||
            stdout.match?(/failed to find `[^`]+\.rs`/) ||
            stdout.match?(/could not find `[^`]+\.rs`/) ||
            stdout.match?(/cannot find binary `[^`]+`/) ||
            stdout.match?(/binary target `[^`]+` not found/) ||
            stdout.include?("Please specify bin.path if you want to use a non-default path") ||
            (stdout.include?("binary target") && stdout.include?("not found"))
        end

        sig { params(message: String).returns(T::Boolean) }
        def using_old_toolchain?(message)
          return true if message.include?("usage of sparse registries requires `-Z sparse-registry`")

          # Detect rustup installation failures for old toolchains (e.g. "syncing channel updates for 1.67-x86_64-...")
          rustup_channel = /syncing channel updates for (?<version>\d+\.\d+)-/.match(message)
          return version_class.new(rustup_channel[:version]) < version_class.new("1.68") if rustup_channel

          version_log = /rust version (?<version>\d.\d+)/.match(message)
          return false unless version_log

          version_class.new(version_log[:version]) < version_class.new("1.68")
        end

        sig { void }
        def write_temporary_dependency_files
          write_temporary_manifest_files
          write_temporary_path_dependency_files

          File.write(lockfile.name, replace_ssh_urls(T.must(lockfile.content)))
          File.write(T.must(toolchain).name, T.must(toolchain).content) if toolchain
          config_files.each do |config_file|
            FileUtils.mkdir_p(File.dirname(config_file.name))
            File.write(
              config_file.name,
              Helpers.sanitize_cargo_config(T.must(config_file.content), file_name: config_file.name)
            )
          end
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

        sig { params(parsed_manifest: T::Hash[String, T.anything]).void }
        def pin_target_specific_dependencies!(parsed_manifest)
          toml_table_or_empty(parsed_manifest.fetch("target", {})).each do |target, t_details|
            t_details = toml_table_or_empty(t_details)
            Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
              toml_table_or_empty(t_details.fetch(type, {})).each do |name, requirement|
                next unless name == dependency.name

                updated_req = "=#{dependency.version}"

                if T.cast(requirement, T.nilable(Object)).is_a?(Hash)
                  toml_table_or_empty(
                    toml_table_or_empty(
                      toml_table_or_empty(
                        toml_table_or_empty(parsed_manifest["target"])[target]
                      )[type]
                    )[name]
                  )["version"] =
                    updated_req
                else
                  toml_table_or_empty(
                    toml_table_or_empty(
                      toml_table_or_empty(parsed_manifest["target"])[target]
                    )[type]
                  )[name] = updated_req
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

        sig { params(value: T.anything).returns(T::Hash[String, T.anything]) }
        def toml_table_or_empty(value)
          obj = T.cast(value, T.nilable(Object))
          obj.is_a?(Hash) ? obj : {}
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

        # Cargo merges `.cargo/config.toml` hierarchically (package directory plus
        # every ancestor up to the repo root), so we materialise all of them and
        # let Cargo perform the merge with its own precedence rules.
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def config_files
          @config_files ||= dependency_files.select { |f| f.name.end_with?(".cargo/config.toml") }
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

          target_line_versions(lockfile_content, dependency).any? do |version|
            dependency.version_class.new(version) > dependency.version_class.new(T.must(dependency.previous_version))
          end
        end

        sig do
          params(lockfile_content: String, dependency: Dependabot::Dependency)
            .returns(T.nilable(String))
        end
        def extract_actual_version(lockfile_content, dependency)
          target_line_versions(lockfile_content, dependency).max_by do |version|
            dependency.version_class.new(version)
          end
        end

        sig do
          params(lockfile_content: String, dependency: Dependabot::Dependency)
            .returns(T::Array[String])
        end
        def target_line_versions(lockfile_content, dependency)
          target_version = dependency.version
          return [] unless target_version && dependency.version_class.correct?(target_version)

          requirements = [dependency.previous_version, target_version].compact.uniq.filter_map do |version|
            dependency.requirement_class.new(version) if dependency.version_class.correct?(version)
          end
          dependency_lockfile_entries(lockfile_content, dependency).filter_map do |entry|
            version = entry[/^version = "([^"]+)"$/, 1]
            next unless version && dependency.version_class.correct?(version)

            parsed_version = dependency.version_class.new(version)
            next unless requirements.any? { |requirement| requirement.satisfied_by?(parsed_version) }

            version
          end
        end

        sig do
          params(lockfile_content: String, dependency: Dependabot::Dependency)
            .returns(T::Array[String])
        end
        def dependency_lockfile_entries(lockfile_content, dependency)
          entries = T.let([], T::Array[String])
          lockfile_content.scan(LOCKFILE_ENTRY_REGEX) do
            entries << Regexp.last_match.to_s
          end
          entries.select! { |entry| entry.match?(/^name = "#{Regexp.escape(dependency.name)}"$/) }

          source = dependency.metadata[:cargo_package_source]
          entries.select! { |entry| entry.include?(%(source = "#{source}")) } if source
          entries
        end

        sig do
          params(updated_lockfile: String, dependency: Dependabot::Dependency)
            .returns(T::Boolean)
        end
        def previous_package_replaced?(updated_lockfile, dependency)
          previous_version = dependency.previous_version
          return true unless previous_version
          return true if previous_version == dependency.version || git_dependency?

          original_content = T.must(lockfile.content)
          return true unless package_version_present?(original_content, dependency, previous_version)

          !package_version_present?(updated_lockfile, dependency, previous_version)
        end

        sig do
          params(lockfile_content: String, dependency: Dependabot::Dependency, version: String)
            .returns(T::Boolean)
        end
        def package_version_present?(lockfile_content, dependency, version)
          dependency_lockfile_entries(lockfile_content, dependency).any? do |entry|
            entry.match?(/^version = "#{Regexp.escape(version)}"$/)
          end
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
