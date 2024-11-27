# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/nuget/native_discovery/native_workspace_discovery"
require "json"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeDiscoveryJsonReader
      extend T::Sig

      sig { returns(T::Hash[String, NativeDiscoveryJsonReader]) }
      def self.discovery_result_cache
        T.let(CacheManager.cache("discovery_json_cache"), T::Hash[String, NativeDiscoveryJsonReader])
      end

      sig { returns(T::Hash[String, String]) }
      def self.discovery_path_cache
        T.let(CacheManager.cache("discovery_path_cache"), T::Hash[String, String])
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).returns(NativeDiscoveryJsonReader)
      end
      def self.get_discovery_from_dependency_files(dependency_files)
        key = create_cache_key(dependency_files)
        discovery_json = discovery_result_cache[key]
        raise "No discovery result for specified dependency files: #{key}" unless discovery_json

        discovery_json
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          discovery: NativeDiscoveryJsonReader
        ).void
      end
      def self.set_discovery_from_dependency_files(dependency_files:, discovery:)
        key = create_cache_key(dependency_files)
        discovery_result_cache[key] = discovery
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).returns(String)
      end
      def self.get_discovery_file_path_from_dependency_files(dependency_files)
        key = create_cache_key(dependency_files)
        discovery_path = discovery_path_cache[key]
        raise "No discovery path found for specified dependency files: #{key}" unless discovery_path

        discovery_path
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).returns(String)
      end
      def self.create_discovery_file_path_from_dependency_files(dependency_files)
        discovery_key = create_cache_key(dependency_files)
        if discovery_path_cache[discovery_key]
          raise "Discovery file path already exists for the given dependency files: #{discovery_key}"
        end

        discovery_counter_cache = T.let(CacheManager.cache("discovery_counter_cache"), T::Hash[String, Integer])
        counter_key = "counter"
        current_counter = discovery_counter_cache[counter_key] || 0
        current_counter += 1
        discovery_counter_cache[counter_key] = current_counter
        incremeted_discovery_file_path = File.join(temp_directory, "discovery.#{current_counter}.json")
        discovery_path_cache[discovery_key] = incremeted_discovery_file_path
        incremeted_discovery_file_path
      end

      # this is a test-only method
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).void
      end
      def self.clear_discovery_file_path_from_cache(dependency_files)
        key = create_cache_key(dependency_files)
        discovery_file_path = discovery_path_cache[key]
        File.delete(discovery_file_path) if discovery_file_path && File.exist?(discovery_file_path)
        discovery_path_cache.delete(key)
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).returns(String)
      end
      def self.create_cache_key(dependency_files)
        dependency_files.map { |d| d.to_h.except("content") }.to_s
      end

      sig { returns(String) }
      def self.temp_directory
        File.join(Dir.tmpdir, ".dependabot")
      end

      sig do
        params(
          discovery_json_path: String
        ).returns(T.nilable(DependencyFile))
      end
      def self.discovery_json_from_path(discovery_json_path)
        return unless File.exist?(discovery_json_path)

        DependencyFile.new(
          name: Pathname.new(discovery_json_path).cleanpath.to_path,
          directory: temp_directory,
          type: "file",
          content: File.read(discovery_json_path)
        )
      end

      sig { returns(T.nilable(NativeWorkspaceDiscovery)) }
      attr_reader :workspace_discovery

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      attr_reader :dependency_set

      sig { params(discovery_json: DependencyFile).void }
      def initialize(discovery_json:)
        @discovery_json = discovery_json
        @workspace_discovery = T.let(read_workspace_discovery, T.nilable(Dependabot::Nuget::NativeWorkspaceDiscovery))
        @dependency_set = T.let(read_dependency_set, Dependabot::FileParsers::Base::DependencySet)
      end

      private

      sig { returns(DependencyFile) }
      attr_reader :discovery_json

      sig { returns(T.nilable(NativeWorkspaceDiscovery)) }
      def read_workspace_discovery
        return nil unless discovery_json.content

        parsed_json = T.let(JSON.parse(T.must(discovery_json.content)), T::Hash[String, T.untyped])
        NativeWorkspaceDiscovery.from_json(parsed_json)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, discovery_json.path
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def read_dependency_set
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new
        return dependency_set unless workspace_discovery

        workspace_result = T.must(workspace_discovery)
        workspace_result.projects.each do |project|
          dependency_set += project.dependency_set
        end
        if workspace_result.dotnet_tools_json
          dependency_set += T.must(workspace_result.dotnet_tools_json).dependency_set
        end
        dependency_set += T.must(workspace_result.global_json).dependency_set if workspace_result.global_json

        dependency_set
      end
    end
  end
end
