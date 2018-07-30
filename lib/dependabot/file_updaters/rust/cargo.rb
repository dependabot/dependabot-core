# frozen_string_literal: true

require "toml-rb"
require "dependabot/git_commit_checker"
require "dependabot/file_updaters/base"
require "dependabot/file_parsers/rust/cargo"
require "dependabot/shared_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileUpdaters
    module Rust
      class Cargo < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^Cargo\.toml$/,
            /^Cargo\.lock$/
          ]
        end

        def updated_dependency_files
          # Returns an array of updated files. Only files that have been updated
          # should be returned.
          updated_files = []

          manifest_files.each do |file|
            next unless file_changed?(file)
            updated_files <<
              updated_file(
                file: file,
                content: updated_manifest_file_content(file)
              )
          end

          if lockfile && updated_lockfile_content != lockfile.content
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          raise "No files changed!" if updated_files.empty?

          updated_files
        end

        private

        def check_required_files
          raise "No Cargo.toml!" unless get_original_file("Cargo.toml")
        end

        # Currently, there will only be a single updated dependency
        def dependency
          dependencies.first
        end

        def updated_manifest_file_content(file)
          dependencies.
            select { |dep| requirement_changed?(file, dep) }.
            reduce(file.content.dup) do |content, dep|
              updated_content = content
              updated_content = update_requirements(
                content: updated_content,
                filename: file.name,
                dependency: dep
              )
              updated_content = update_git_pin(
                content: updated_content,
                filename: file.name,
                dependency: dep
              )

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end

        def update_requirements(content:, filename:, dependency:)
          updated_content = content.dup

          # The UpdateChecker ensures the order of requirements is preserved
          # when updating, so we can zip them together in new/old pairs.
          reqs = dependency.requirements.zip(dependency.previous_requirements).
                 reject { |new_req, old_req| new_req == old_req }

          # Loop through each changed requirement
          reqs.each do |new_req, old_req|
            raise "Bad req match" unless new_req[:file] == old_req[:file]
            next if new_req[:requirement] == old_req[:requirement]
            next unless new_req[:file] == filename

            updated_content = update_manifest_req(
              content: updated_content,
              dep: dependency,
              old_req: old_req.fetch(:requirement),
              new_req: new_req.fetch(:requirement)
            )
          end

          updated_content
        end

        def update_git_pin(content:, filename:, dependency:)
          updated_pin =
            dependency.requirements.
            find { |r| r[:file] == filename }&.
            dig(:source, :ref)

          old_pin =
            dependency.previous_requirements.
            find { |r| r[:file] == filename }&.
            dig(:source, :ref)

          return content unless old_pin

          update_manifest_pin(
            content: content,
            dep: dependency,
            old_pin: old_pin,
            new_pin: updated_pin
          )
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            SharedHelpers.in_a_temporary_directory do
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

        def handle_cargo_error(error)
          raise unless error.message.include?("no matching version")
          raise if error.message.include?("`#{dependency.name}`")
          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        def update_manifest_req(content:, dep:, old_req:, new_req:)
          simple_declaration = content.scan(declaration_regex(dep)).
                               find { |m| m.include?(old_req) }

          if simple_declaration
            content.gsub(simple_declaration) do |line|
              line.gsub(old_req, new_req)
            end
          elsif content.match?(feature_declaration_version_regex(dep))
            content.gsub(feature_declaration_version_regex(dep)) do |part|
              line = content.match(feature_declaration_version_regex(dep)).
                     named_captures.fetch("version_declaration")
              new_line = line.gsub(old_req, new_req)
              part.gsub(line, new_line)
            end
          else
            content
          end
        end

        def update_manifest_pin(content:, dep:, old_pin:, new_pin:)
          simple_declaration = content.scan(declaration_regex(dep)).
                               find { |m| m.include?(old_pin) }

          if simple_declaration
            content.gsub(simple_declaration) do |line|
              line.gsub(old_pin, new_pin)
            end
          elsif content.match?(feature_declaration_pin_regex(dep))
            content.gsub(feature_declaration_pin_regex(dep)) do |part|
              line = content.match(feature_declaration_pin_regex(dep)).
                     named_captures.fetch("pin_declaration")
              new_line = line.gsub(old_pin, new_pin)
              part.gsub(line, new_line)
            end
          else
            content
          end
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
          raw_response = nil
          IO.popen(command, err: %i(child out)) do |process|
            raw_response = process.read
          end

          # Raise an error with the output from the shell session if Cargo
          # returns a non-zero status
          return if $CHILD_STATUS.success?
          raise SharedHelpers::HelperSubprocessFailed.new(
            raw_response,
            command
          )
        end

        def write_temporary_dependency_files
          write_temporary_manifest_files
          write_temporary_path_dependency_files

          File.write(lockfile.name, lockfile.content)
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
          updated_content = updated_manifest_file_content(file)
          updated_content = pin_version(updated_content) unless git_dependency?
          updated_content = replace_ssh_urls(updated_content)
          updated_content
        end

        def prepared_path_dependency_content(file)
          updated_content = file.content.dup
          updated_content = replace_ssh_urls(updated_content)
          updated_content
        end

        def pin_version(content)
          parsed_manifest = TomlRB.parse(content)

          FileParsers::Rust::Cargo::DEPENDENCY_TYPES.each do |type|
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

            FileParsers::Rust::Cargo::DEPENDENCY_TYPES.each do |type|
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

        def declaration_regex(dep)
          /(?:^|["'])#{Regexp.escape(dep.name)}["']?\s*=.*$/i
        end

        def feature_declaration_version_regex(dep)
          /
            #{Regexp.quote("dependencies.#{dep.name}]")}
            (?:(?!^\[).)+
            (?<version_declaration>version\s*=.*)$
          /mx
        end

        def feature_declaration_pin_regex(dep)
          /
            #{Regexp.quote("dependencies.#{dep.name}]")}
            (?:(?!^\[).)+
            (?<pin_declaration>(?:tag|rev)\s*=.*)$
          /mx
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
            reject { |f| f.type == "path_dependency" }
        end

        def path_dependency_files
          @path_dependency_files ||=
            dependency_files.
            select { |f| f.type == "path_dependency" }
        end

        def lockfile
          @lockfile ||= get_original_file("Cargo.lock")
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
