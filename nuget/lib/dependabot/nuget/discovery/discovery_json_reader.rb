# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/nuget/discovery/workspace_discovery"
require "json"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class DiscoveryJsonReader
      extend T::Sig

      DISCOVERY_JSON_PATH = ".dependabot/discovery.json"

      sig { returns(String) }
      private_class_method def self.temp_directory
        Dir.tmpdir
      end

      sig { returns(String) }
      def self.discovery_file_path
        File.join(temp_directory, DISCOVERY_JSON_PATH)
      end

      sig { returns(T.nilable(DependencyFile)) }
      def self.discovery_json
        return unless File.exist?(discovery_file_path)

        DependencyFile.new(
          name: Pathname.new(discovery_file_path).cleanpath.to_path,
          directory: temp_directory,
          type: "file",
          content: File.read(discovery_file_path)
        )
      end

      sig { params(discovery_json: DependencyFile).void }
      def initialize(discovery_json:)
        @discovery_json = discovery_json
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def dependency_set
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new
        return dependency_set unless workspace_discovery

        workspace_result = T.must(workspace_discovery)
        workspace_result.projects.each do |project|
          dependency_set += project.dependency_set
        end
        if workspace_result.directory_packages_props
          dependency_set += T.must(workspace_result.directory_packages_props).dependency_set
        end
        if workspace_result.dotnet_tools_json
          dependency_set += T.must(workspace_result.dotnet_tools_json).dependency_set
        end
        dependency_set += T.must(workspace_result.global_json).dependency_set if workspace_result.global_json

        dependency_set
      end

      sig { returns(T.nilable(WorkspaceDiscovery)) }
      def workspace_discovery
        @workspace_discovery ||= T.let(begin
          return nil unless discovery_json.content

          Dependabot.logger.info("Discovery JSON content: #{discovery_json.content}")
          puts "Discovery JSON content: #{discovery_json.content}"

          parsed_json = T.let(JSON.parse(T.must(discovery_json.content)), T::Hash[String, T.untyped])
          WorkspaceDiscovery.from_json(parsed_json)
        end, T.nilable(WorkspaceDiscovery))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, discovery_json.path
      end

      private

      sig { returns(DependencyFile) }
      attr_reader :discovery_json
    end
  end
end
