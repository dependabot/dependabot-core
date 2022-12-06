# frozen_string_literal: true

require "toml-rb"
require "open3"
require "dependabot/shared_helpers"
require "dependabot/cargo/update_checker"
require "dependabot/cargo/file_parser"
require "dependabot/cargo/version"
require "dependabot/errors"
module Dependabot
  module Cargo
    class UpdateChecker
      class VersionResolver
        UNABLE_TO_UPDATE = /Unable to update (?<url>.*?)$/
        BRANCH_NOT_FOUND_REGEX = /#{UNABLE_TO_UPDATE}.*to find branch `(?<branch>[^`]+)`/m
        REVSPEC_PATTERN = /revspec '.*' not found/
        OBJECT_PATTERN = /object not found - no match for id \(.*\)/
        REF_NOT_FOUND_REGEX = /#{UNABLE_TO_UPDATE}.*(#{REVSPEC_PATTERN}|#{OBJECT_PATTERN})/m
        GIT_REF_NOT_FOUND_REGEX = /Updating git repository `(?<url>[^`]*)`.*fatal: couldn't find remote ref/m

        def initialize(dependency:, credentials:,
                       original_dependency_files:, prepared_dependency_files:)
          @dependency = dependency
          @prepared_dependency_files = prepared_dependency_files
          @original_dependency_files = original_dependency_files
          @credentials = credentials
        end

        def latest_resolvable_version
          return @latest_resolvable_version if defined?(@latest_resolvable_version)

          @latest_resolvable_version = fetch_latest_resolvable_version
        end

        private

        attr_reader :dependency, :credentials,
                    :prepared_dependency_files, :original_dependency_files

        def fetch_latest_resolvable_version
          base_directory = prepared_dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_cargo_update_command
            end

            updated_version = fetch_version_from_new_lockfile

            return if updated_version.nil?
            return updated_version if git_dependency?

            version_class.new(updated_version)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry if better_specification_needed?(e)
          handle_cargo_errors(e)
        end

        def fetch_version_from_new_lockfile
          check_rust_workspace_root unless File.exist?("Cargo.lock")
          lockfile_content = File.read("Cargo.lock")
          versions = TomlRB.parse(lockfile_content).fetch("package").
                     select { |p| p["name"] == dependency.name }

          updated_version =
            if dependency.top_level?
              versions.max_by { |p| version_class.new(p.fetch("version")) }
            else
              versions.min_by { |p| version_class.new(p.fetch("version")) }
            end

          return unless updated_version

          if git_dependency?
            updated_version.fetch("source").split("#").last
          else
            updated_version.fetch("version")
          end
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/AbcSize
        def better_specification_needed?(error)
          return false if @custom_specification
          return false unless error.message.match?(/specification .* is ambigu/)

          spec_options = error.message.gsub(/.*following:\n/m, "").
                         lines.map(&:strip)

          ver = if git_dependency? && git_dependency_version
                  git_dependency_version
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
            spec += ":#{git_dependency_version}" if git_dependency_version
          elsif dependency.version
            spec += ":#{dependency.version}"
            spec = "https://github.com/rust-lang/crates.io-index#" + spec
          end

          spec
        end

        # Shell out to Cargo, which handles everything for us, and does
        # so without doing an install (so it's fast).
        def run_cargo_update_command
          run_cargo_command(
            "cargo update -p #{dependency_spec} --verbose",
            fingerprint: "cargo update -p <dependency_spec> --verbose"
          )
        end

        def run_cargo_command(command, fingerprint: nil)
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

        def write_temporary_dependency_files(prepared: true)
          write_manifest_files(prepared: prepared)

          File.write(lockfile.name, lockfile.content) if lockfile
          File.write(toolchain.name, toolchain.content) if toolchain
        end

        def check_rust_workspace_root
          cargo_toml = original_dependency_files.
                       select { |f| f.name.end_with?("../Cargo.toml") }.
                       max_by { |f| f.name.length }
          return unless TomlRB.parse(cargo_toml.content)["workspace"]

          msg = "This project is part of a Rust workspace but is not the " \
                "workspace root." \

          if cargo_toml.directory != "/"
            msg += "Please update your settings so Dependabot points at the " \
                   "workspace root instead of #{cargo_toml.directory}."
          end
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/PerceivedComplexity
        def handle_cargo_errors(error)
          if error.message.include?("does not have these features")
            # TODO: Ideally we should update the declaration not to ask
            # for the specified features
            return nil
          end

          if error.message.include?("authenticate when downloading repo") ||
             error.message.include?("fatal: Authentication failed for")
            # Check all dependencies for reachability (so that we raise a
            # consistent error)
            urls = unreachable_git_urls

            if urls.none?
              url = error.message.match(UNABLE_TO_UPDATE).
                    named_captures.fetch("url").split(/[#?]/).first
              raise if reachable_git_urls.include?(url)

              urls << url
            end

            raise Dependabot::GitDependenciesNotReachable, urls
          end

          [BRANCH_NOT_FOUND_REGEX, REF_NOT_FOUND_REGEX, GIT_REF_NOT_FOUND_REGEX].each do |regex|
            next unless error.message.match?(regex)

            dependency_url = error.message.match(regex).named_captures.fetch("url").split(/[#?]/).first
            raise Dependabot::GitDependencyReferenceNotFound, dependency_url
          end

          if workspace_native_library_update_error?(error.message)
            # This happens when we're updating one part of a workspace which
            # triggers an update of a subdependency that uses a native library,
            # whilst leaving another part of the workspace using an older
            # version. Ideally we would prevent the subdependency update.
            return nil
          end

          if git_dependency? && error.message.include?("no matching package")
            # This happens when updating a git dependency whose version has
            # changed from a release to a pre-release version
            return nil
          end

          if error.message.include?("all possible versions conflict")
            # This happens when a top-level requirement locks us to an old
            # patch release of a dependency that is a sub-dep of what we're
            # updating. It's (probably) a Cargo bug.
            return nil
          end

          raise Dependabot::DependencyFileNotResolvable, error.message if resolvability_error?(error.message)

          raise error
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        def unreachable_git_urls
          return @unreachable_git_urls if defined?(@unreachable_git_urls)

          @unreachable_git_urls = []
          @reachable_git_urls = []

          dependencies = FileParser.new(
            dependency_files: original_dependency_files,
            source: nil
          ).parse

          dependencies.each do |dep|
            checker = GitCommitChecker.new(
              dependency: dep,
              credentials: credentials
            )
            next unless checker.git_dependency?

            url = dep.requirements.find { |r| r.dig(:source, :type) == "git" }.
                  fetch(:source).fetch(:url)

            if checker.git_repo_reachable?
              @reachable_git_urls << url
            else
              @unreachable_git_urls << url
            end
          end

          @unreachable_git_urls
        end

        def reachable_git_urls
          return @reachable_git_urls if defined?(@reachable_git_urls)

          unreachable_git_urls
          @reachable_git_urls
        end

        def resolvability_error?(message)
          return true if message.include?("failed to parse lock")
          return true if message.include?("believes it's in a workspace")
          return true if message.include?("wasn't a root")
          return true if message.include?("requires a nightly version")
          return true if message.match?(/feature `[^\`]+` is required/)
          return true if message.include?("unexpected end of input while parsing major version number")

          !original_requirements_resolvable?
        end

        def original_requirements_resolvable?
          base_directory = original_dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files(prepared: false)

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_cargo_update_command
            end
          end

          true
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise unless e.message.include?("no matching version") ||
                       e.message.include?("failed to select a version") ||
                       e.message.include?("no matching package named") ||
                       e.message.include?("failed to parse manifest") ||
                       e.message.include?("failed to update submodule")

          false
        end

        def workspace_native_library_update_error?(message)
          return unless message.include?("native library")

          library_count = prepared_manifest_files.count do |file|
            package_name = TomlRB.parse(file.content).dig("package", "name")
            next false unless package_name

            message.include?("depended on by `#{package_name} ")
          end

          library_count >= 2
        end

        def write_manifest_files(prepared: true)
          manifest_files = if prepared then prepared_manifest_files
                           else
                             original_manifest_files
                           end

          manifest_files.each do |file|
            path = file.name
            dir = Pathname.new(path).dirname
            FileUtils.mkdir_p(dir)
            File.write(file.name, sanitized_manifest_content(file.content))

            next if virtual_manifest?(file)

            File.write(File.join(dir, "build.rs"), dummy_app_content)

            FileUtils.mkdir_p(File.join(dir, "src"))
            File.write(File.join(dir, "src/lib.rs"), dummy_app_content)
            File.write(File.join(dir, "src/main.rs"), dummy_app_content)
          end
        end

        def git_dependency_version
          return unless lockfile

          TomlRB.parse(lockfile.content).
            fetch("package", []).
            select { |p| p["name"] == dependency.name }.
            find { |p| p["source"].end_with?(dependency.version) }.
            fetch("version")
        end

        def git_source_url
          dependency.requirements.
            find { |r| r.dig(:source, :type) == "git" }&.
            dig(:source, :url)
        end

        def dummy_app_content
          %{fn main() {\nprintln!("Hello, world!");\n}}
        end

        def sanitized_manifest_content(content)
          object = TomlRB.parse(content)

          object.delete("bin")

          object["package"].delete("default-run") if object.dig("package", "default-run")

          package_name = object.dig("package", "name")
          return TomlRB.dump(object) unless package_name&.match?(/[\{\}]/)

          raise "Sanitizing name for pkg with lockfile. Investigate!" if lockfile

          object["package"]["name"] = "sanitized"
          TomlRB.dump(object)
        end

        def prepared_manifest_files
          @prepared_manifest_files ||=
            prepared_dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }
        end

        def original_manifest_files
          @original_manifest_files ||=
            original_dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }
        end

        def lockfile
          @lockfile ||= prepared_dependency_files.
                        find { |f| f.name == "Cargo.lock" }
        end

        def toolchain
          @toolchain ||= prepared_dependency_files.
                         find { |f| f.name == "rust-toolchain" }
        end

        def git_dependency?
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end

        # When the package table is not present in a workspace manifest, it is
        # called a virtual manifest: https://doc.rust-lang.org/cargo/reference/
        # manifest.html#virtual-manifest
        def virtual_manifest?(file)
          !file.content.include?("[package]")
        end

        def version_class
          Cargo::Version
        end
      end
    end
  end
end
