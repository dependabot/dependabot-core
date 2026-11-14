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
        requirements_by_tool = T.let({}, T::Hash[String, T::Array[Dependabot::DependencyRequirement]])
        mise_files.each { |mise_file| collect_requirements(mise_file, requirements_by_tool) }

        requirements_by_tool.map do |tool_name, requirements|
          Dependabot::Dependency.new(
            name: tool_name,
            version: lowest_resolved_version(requirements),
            package_manager: "mise",
            requirements: requirements
          )
        end
      end

      private

      sig do
        params(
          mise_file: Dependabot::DependencyFile,
          requirements_by_tool: T::Hash[String, T::Array[Dependabot::DependencyRequirement]]
        )
          .void
      end
      def collect_requirements(mise_file, requirements_by_tool)
        tools = supported_tools(mise_file)
        return if tools.empty?

        Dependabot::SharedHelpers.in_a_temporary_directory do
          # With the lockfile present, mise reports the locked version of loose pins such as "20".
          write_manifest_files([mise_file, lockfile_for(mise_file)].compact)

          listed = T.cast(JSON.parse(run_mise_ls(mise_file)), T::Hash[String, Object])
          tools.each_key do |tool_name|
            entry = tool_entries(mise_file, listed, tool_name).first
            next unless entry.is_a?(Hash)

            requested = entry["requested_version"]
            next unless requested
            # Skip fuzzy pins like "latest" or "lts"
            next unless Dependabot::Mise::Version.correct?(requested)

            (requirements_by_tool[tool_name] ||= []) << Dependabot::DependencyRequirement.create(
              requirement: requested,
              file: mise_file.name,
              groups: [],
              source: nil,
              metadata: { resolved_version: entry["version"] || requested }
            )
          end
        end
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed, JSON::ParserError => e
        raise Dependabot::DependencyFileNotParseable.new(mise_file.name, e.message)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def mise_files
        dependency_files.select { |f| Dependabot::Mise::FileFetcher.mise_config_file?(f.name) }
      end

      sig { params(mise_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile_for(mise_file)
        lockfile_name = Dependabot::Mise::FileFetcher.lockfile_path_for(mise_file.name)
        dependency_files.find { |file| file.name == lockfile_name }
      end

      # Safe mode rejects templates, and relocking has to load every manifest sharing a lockfile.
      sig { params(mise_file: Dependabot::DependencyFile).returns(T::Hash[String, Object]) }
      def supported_tools(mise_file)
        tools = manifest_tools(mise_file)
        reason = if templated?(tools)
                   "templates in [tools] are not supported"
                 elsif (sibling = templated_lockfile_sibling(mise_file))
                   "it shares a lockfile with #{sibling.name}, which uses templates in [tools]"
                 end
        return tools unless reason

        Dependabot.logger.warn("Skipping #{mise_file.name}: #{reason}")
        {}
      end

      sig { params(mise_file: Dependabot::DependencyFile).returns(T.nilable(Dependabot::DependencyFile)) }
      def templated_lockfile_sibling(mise_file)
        lockfile = lockfile_for(mise_file)
        return unless lockfile

        mise_files.find do |other|
          other.name != mise_file.name && lockfile_for(other)&.name == lockfile.name &&
            templated?(manifest_tools(other))
        end
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
        command = ["mise", "ls", "--current", "--no-global", "--json"]
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

      sig { params(requirements: T::Array[Dependabot::DependencyRequirement]).returns(T.nilable(String)) }
      def lowest_resolved_version(requirements)
        requirements.filter_map { |req| req.metadata_string("resolved_version") }
                    .min_by { |version| Dependabot::Mise::Version.new(version) }
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
