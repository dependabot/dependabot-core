# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/helpers"
require "dependabot/mise/version"
require "dependabot/shared_helpers"
require "json"

module Dependabot
  module Mise
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig
      include Dependabot::Mise::Helpers

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies_by_name = {}
        mise_files = dependency_files.select { |f| Dependabot::Mise::FileFetcher.mise_config_file?(f.name) }

        # Parse each mise config file in isolation to track which file each dependency comes from
        mise_files.each do |mise_file|
          parse_mise_file(mise_file, dependencies_by_name)
        end

        dependencies_by_name.values
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn("mise ls failed: #{e.message}")
        []
      rescue JSON::ParserError => e
        Dependabot.logger.warn("mise ls returned invalid JSON: #{e.message}")
        []
      end

      private

      sig do
        params(
          mise_file: Dependabot::DependencyFile,
          dependencies_by_name: T::Hash[String, Dependabot::Dependency]
        )
          .void
      end
      def parse_mise_file(mise_file, dependencies_by_name)
        # Parse this file in isolation by writing only this file to a temp directory
        Dependabot::SharedHelpers.in_a_temporary_directory do
          File.write(mise_file.name, mise_file.content)

          raw = Dependabot::SharedHelpers.run_shell_command(
            "mise ls --current --local --json",
            stderr_to_stdout: false,
            env: { "MISE_YES" => "1" }
          )

          JSON.parse(raw).each do |tool_name, entries|
            entry = Array(entries).first
            next unless entry

            requested = entry["requested_version"]
            next unless requested
            # Skip fuzzy pins like "latest" or "lts"
            next unless Dependabot::Mise::Version.correct?(requested)

            resolved = entry["version"] || requested

            # Add or update the dependency with this file's requirement
            dependencies_by_name[tool_name] = if dependencies_by_name[tool_name]
                                                # Tool already exists from another file, add this file's requirement
                                                add_requirement_to_dependency(
                                                  T.must(dependencies_by_name[tool_name]),
                                                  mise_file.name,
                                                  requested,
                                                  resolved
                                                )
                                              else
                                                # New tool, create dependency
                                                build_dependency(
                                                  tool_name,
                                                  resolved,
                                                  requested,
                                                  mise_file.name
                                                )
                                              end
          end
        end
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          file_name: String,
          requirement: String,
          version: String
        )
          .returns(Dependabot::Dependency)
      end
      def add_requirement_to_dependency(dependency, file_name, requirement, version)
        # Check if we already have this file in requirements (shouldn't happen, but be safe)
        return dependency if dependency.requirements.any? { |r| r[:file] == file_name }

        # Add the new requirement for this file
        new_requirement = {
          requirement: requirement,
          file: file_name,
          groups: [],
          source: nil
        }

        updated_requirements = dependency.requirements + [new_requirement]

        # Use the LOWEST version across all files
        # This ensures Dependabot will suggest updates for files that are behind
        # If we used the highest, files already on latest wouldn't trigger updates for outdated files
        current_version = Dependabot::Mise::Version.new(dependency.version)
        new_version = Dependabot::Mise::Version.new(version)
        updated_version = new_version < current_version ? version : dependency.version

        # Create a new Dependency object with updated requirements and version
        Dependabot::Dependency.new(
          name: dependency.name,
          version: updated_version,
          package_manager: dependency.package_manager,
          requirements: updated_requirements
        )
      end

      sig do
        params(name: String, version: String, requirement: String, file_name: String)
          .returns(Dependabot::Dependency)
      end
      def build_dependency(name, version, requirement, file_name)
        Dependabot::Dependency.new(
          name: name,
          version: version,
          package_manager: "mise",
          requirements: [{
            requirement: requirement,
            file: file_name,
            groups: [],
            source: nil
          }]
        )
      end

      sig { override.void }
      def check_required_files
        mise_files = dependency_files.select { |f| Dependabot::Mise::FileFetcher.mise_config_file?(f.name) }
        return unless mise_files.empty?

        raise "No mise configuration file found!"
      end
    end
  end
end

Dependabot::FileParsers.register("mise", Dependabot::Mise::FileParser)
