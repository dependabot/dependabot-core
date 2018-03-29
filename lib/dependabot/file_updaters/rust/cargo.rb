# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

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

          if file_changed?(cargo_toml)
            updated_files <<
              updated_file(
                file: cargo_toml,
                content: updated_cargo_toml_content
              )
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

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

        def updated_cargo_toml_content
          dependencies.
            select { |dep| requirement_changed?(cargo_toml, dep) }.
            reduce(cargo_toml.content.dup) do |content, dep|
              updated_requirement =
                dep.requirements.
                find { |r| r[:file] == cargo_toml.name }.
                fetch(:requirement)

              old_req =
                dep.previous_requirements.
                find { |r| r[:file] == cargo_toml.name }.
                fetch(:requirement)

              updated_content =
                content.gsub(declaration_regex(dep)) do |line|
                  line.gsub(old_req, updated_requirement)
                end

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              # Shell out to Cargo, which handles everything for us, and does
              # so without doing an install (so it's fast).
              command = "cargo update -p #{dependency.name}"
              raw_response = nil
              IO.popen(command, err: %i(child out)) do |process|
                raw_response = process.read
              end

              # Raise an error with the output from the shell session if Cargo
              # returns a non-zero status
              unless $CHILD_STATUS.success?
                raise SharedHelpers::HelperSubprocessFailed.new(
                  raw_response,
                  command
                )
              end

              File.read("Cargo.lock")
            end
        end

        def write_temporary_dependency_files
          File.write(cargo_toml.name, updated_cargo_toml_content)
          File.write(lockfile.name, lockfile.content)

          path_dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, file.content)
          end

          FileUtils.mkdir_p("src")
          File.write("src/lib.rs", dummy_app_content)
          File.write("src/main.rs", dummy_app_content)
        end

        def dummy_app_content
          %{fn main() {\nprintln!("Hello, world!");\n}}
        end

        def declaration_regex(dep)
          /(?:^|["'])#{Regexp.escape(dep.name)}["']?\s*=.*$/i
        end

        def cargo_toml
          @cargo_toml ||= get_original_file("Cargo.toml")
        end

        def path_dependency_files
          dependency_files.
            select { |f| f.name.end_with?("Cargo.toml") }.
            reject { |f| f.name == "Cargo.toml" }
        end

        def lockfile
          @lockfile ||= get_original_file("Cargo.lock")
        end
      end
    end
  end
end
