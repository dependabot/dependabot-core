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
                         unlock_requirement: true,
                         replacement_git_pin: nil)
            @dependency_files = dependency_files
            @dependency = dependency
            @unlock_requirement = unlock_requirement
            @replacement_git_pin = replacement_git_pin
          end

          def prepared_dependency_files
            files = []
            files += manifest_files.map do |file|
              DependencyFile.new(
                name: file.name,
                content: manifest_content_for_update_check(file),
                directory: file.directory
              )
            end
            files << lockfile if lockfile
            files
          end

          private

          attr_reader :dependency_files, :dependency, :replacement_git_pin

          def unlock_requirement?
            @unlock_requirement
          end

          def replace_git_pin?
            !replacement_git_pin.nil?
          end

          def manifest_content_for_update_check(file)
            content = file.content

            content = relax_version(file.content) if unlock_requirement?
            content = replace_git_pin(content) if replace_git_pin?
            content = replace_ssh_urls(content)

            content
          end

          # Note: We don't need to care about formatting in this method, since
          # we're only using the manifest to find the latest resolvable version
          def relax_version(content)
            parsed_manifest = TomlRB.parse(content)

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

          def replace_git_pin(content)
            parsed_manifest = TomlRB.parse(content)

            FileParsers::Rust::Cargo::DEPENDENCY_TYPES.each do |type|
              next unless (req = parsed_manifest.dig(type, dependency.name))
              next unless req.is_a?(Hash)
              next unless [req["tag"], req["rev"]].compact.uniq.count == 1

              if req["tag"]
                parsed_manifest[type][dependency.name]["tag"] =
                  replacement_git_pin
              end

              if req["rev"]
                parsed_manifest[type][dependency.name]["rev"] =
                  replacement_git_pin
              end
            end

            TomlRB.dump(parsed_manifest)
          end

          def replace_ssh_urls(content)
            parsed_manifest = TomlRB.parse(content)

            FileParsers::Rust::Cargo::DEPENDENCY_TYPES.each do |type|
              (parsed_manifest[type] || {}).each do |_, details|
                next unless details.is_a?(Hash)
                next unless details["git"]

                details["git"] = details["git"].
                                 gsub(%r{ssh://git@(.*?)/}, 'https://\1/')
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
