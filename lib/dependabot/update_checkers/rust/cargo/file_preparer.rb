# frozen_string_literal: true

require "toml-rb"
require "dependabot/dependency_file"
require "dependabot/file_parsers/rust/cargo"
require "dependabot/update_checkers/rust/cargo"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo
        # This class takes a set of dependency files and sanitizes them for use
        # in UpdateCheckers::Rust::Cargo.
        class FilePreparer
          def initialize(dependency_files:, dependency:,
                         unlock_requirement: true)
            @dependency_files = dependency_files
            @dependency = dependency
            @unlock_requirement = unlock_requirement
          end

          def prepared_dependency_files
            files = []
            files += manifest_files.map do |file|
              DependencyFile.new(
                name: file.name,
                content: updated_manifest_file_content(file),
                directory: file.directory
              )
            end
            files << lockfile if lockfile
            files
          end

          private

          attr_reader :dependency_files, :dependency

          def unlock_requirement?
            @unlock_requirement
          end

          # Note: We don't need to care about formatting in this method, since
          # we're only using the manifest to find the latest resolvable version
          def updated_manifest_file_content(file)
            return file.content unless unlock_requirement?
            parsed_manifest = TomlRB.parse(file.content)

            FileParsers::Rust::Cargo::DEPENDENCY_TYPES.each do |type|
              next unless (req = parsed_manifest.dig(type, dependency.name))
              updated_req = temporary_requirement_for_resolution

              if req.is_a?(Hash)
                parsed_manifest[type][dependency.name]["version"] = updated_req
              else
                parsed_manifest[type][dependency.name] = updated_req
              end
            end

            TomlRB.dump(parsed_manifest)
          end

          def temporary_requirement_for_resolution
            if git_dependency? && git_dependency_version
              ">= #{git_dependency_version}"
            elsif !git_dependency? && dependency.version
              ">= #{dependency.version}"
            elsif !git_dependency?
              ">= 0"
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

          def manifest_files
            @manifest_files ||=
              dependency_files.select { |f| f.name.end_with?("Cargo.toml") }

            raise "No Cargo.toml!" if @manifest_files.none?
            @manifest_files
          end

          def lockfile
            @lockfile ||= dependency_files.find { |f| f.name == "Cargo.lock" }
          end

          def git_dependency?
            GitCommitChecker.
              new(dependency: dependency, credentials: []).
              git_dependency?
          end
        end
      end
    end
  end
end
