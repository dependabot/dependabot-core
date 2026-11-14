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
require "toml-rb"

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
        tools = supported_tools(mise_file)
        return if tools.empty?

        # Parse this file in isolation by writing only this file to a temp directory
        Dependabot::SharedHelpers.in_a_temporary_directory do
          write_manifest_files([mise_file])

          listed = T.cast(JSON.parse(run_mise_ls(mise_file)), T::Hash[String, Object])
          tools.each_key do |tool_name|
            entry = tool_entries(mise_file, listed, tool_name).first
            next unless entry.is_a?(Hash)

            requested = entry["requested_version"]
            next unless requested
            # Skip fuzzy pins like "latest" or "lts"
            next unless Dependabot::Mise::Version.correct?(requested)

            resolved = entry["version"] || requested

            dependency = dependencies_by_name[tool_name]
            dependencies_by_name[tool_name] =
              if dependency
                add_requirement_to_dependency(dependency, mise_file.name, requested, resolved)
              else
                build_dependency(tool_name, resolved, requested, mise_file.name)
              end
          end
        end
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed, JSON::ParserError => e
        raise Dependabot::DependencyFileNotParseable.new(mise_file.name, e.message)
      end

      # Safe mode rejects most templates, and the updater can't rewrite templated values.
      sig { params(mise_file: Dependabot::DependencyFile).returns(T::Hash[String, Object]) }
      def supported_tools(mise_file)
        tools = manifest_tools(mise_file)
        return tools unless templated?(tools)

        Dependabot.logger.warn("Skipping #{mise_file.name}: templates in [tools] are not supported")
        {}
      end

      sig { params(value: Object).returns(T::Boolean) }
      def templated?(value)
        case value
        when String then value.match?(/\{[{%#]/)
        when Hash then value.values.any? { |item| templated?(item) }
        when Array then value.any? { |item| templated?(item) }
        else false
        end
      end

      # Prefer the full listing: filtering can reject uninstalled plugins such as `op`.
      # Query missing keys separately because mise renames aliases such as `golang` to `go`.
      sig do
        params(
          mise_file: Dependabot::DependencyFile,
          listed: T::Hash[String, Object],
          tool_name: String
        ).returns(T::Array[Object])
      end
      def tool_entries(mise_file, listed, tool_name)
        entries = listed.fetch(tool_name) { T.cast(JSON.parse(run_mise_ls(mise_file, tool_name)), Object) }
        entries.is_a?(Array) ? entries : []
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn("mise ls failed for #{tool_name} in #{mise_file.name}: #{e.message}")
        []
      end

      sig { params(mise_file: Dependabot::DependencyFile, tool_name: T.nilable(String)).returns(String) }
      def run_mise_ls(mise_file, tool_name = nil)
        command = ["mise", "ls", "--current", "--local", "--json"]
        command += ["--", tool_name] if tool_name

        Dependabot::SharedHelpers.run_shell_command(
          command,
          stderr_to_stdout: false,
          env: {
            "MISE_YES" => "1",
            "MISE_SAFE" => "1",
            "MISE_OVERRIDE_CONFIG_FILENAMES" => mise_file.name
          }
        )
      end

      sig { params(mise_file: Dependabot::DependencyFile).returns(T::Hash[String, Object]) }
      def manifest_tools(mise_file)
        tools = T.cast(TomlRB.parse(T.must(mise_file.content)), T::Hash[String, Object])["tools"]
        tools.is_a?(Hash) ? tools : {}
      rescue TomlRB::Error => e
        raise Dependabot::DependencyFileNotParseable.new(mise_file.name, e.message)
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
        return dependency if dependency.requirements.any? { |r| r.file == file_name }

        # Add the new requirement for this file
        new_requirement = Dependabot::DependencyRequirement.create(
          requirement: requirement,
          file: file_name,
          groups: [],
          source: nil,
          metadata: { resolved_version: version }
        )

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
            source: nil,
            metadata: { resolved_version: version }
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
