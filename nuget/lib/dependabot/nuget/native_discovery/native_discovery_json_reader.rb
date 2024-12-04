# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/nuget/cache_manager"
require "dependabot/nuget/native_discovery/native_workspace_discovery"
require "json"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeDiscoveryJsonReader
      extend T::Sig

      sig { returns(T::Hash[String, NativeDiscoveryJsonReader]) }
      def self.cache_directory_to_discovery_json_reader
        CacheManager.cache("cache_directory_to_discovery_json_reader")
      end

      sig { returns(T::Hash[String, NativeDiscoveryJsonReader]) }
      def self.cache_dependency_file_paths_to_discovery_json_reader
        CacheManager.cache("cache_dependency_file_paths_to_discovery_json_reader")
      end

      sig { returns(T::Hash[String, String]) }
      def self.cache_dependency_file_paths_to_discovery_json_path
        CacheManager.cache("cache_dependency_file_paths_to_discovery_json_path")
      end

      sig { void }
      def self.testonly_clear_caches
        cache_directory_to_discovery_json_reader.clear
        cache_dependency_file_paths_to_discovery_json_reader.clear
        cache_dependency_file_paths_to_discovery_json_path.clear
      end

      sig { void }
      def self.testonly_clear_discovery_files
        # this will get recreated when necessary
        FileUtils.rm_rf(discovery_directory)
      end

      # Runs NuGet dependency discovery in the given directory and returns a new instance of NativeDiscoveryJsonReader.
      # The location of the resultant JSON file is saved.
      sig do
        params(
          repo_contents_path: String,
          directory: String,
          credentials: T::Array[Dependabot::Credential]
        ).returns(NativeDiscoveryJsonReader)
      end
      def self.run_discovery_in_directory(repo_contents_path:, directory:, credentials:)
        # run discovery
        job_file_path = ENV.fetch("DEPENDABOT_JOB_PATH")
        discovery_json_path = discovery_file_path_from_workspace_path(directory)
        unless File.exist?(discovery_json_path)
          NativeHelpers.run_nuget_discover_tool(job_path: job_file_path,
                                                repo_root: repo_contents_path,
                                                workspace_path: directory,
                                                output_path: discovery_json_path,
                                                credentials: credentials)

          Dependabot.logger.info("Discovery JSON content: #{File.read(discovery_json_path)}")
        end
        load_discovery_for_directory(repo_contents_path: repo_contents_path, directory: directory)
      end

      # Loads NuGet dependency discovery for the given directory and returns a new instance of
      # NativeDiscoveryJsonReader and caches the resultant object.
      sig { params(repo_contents_path: String, directory: String).returns(NativeDiscoveryJsonReader) }
      def self.load_discovery_for_directory(repo_contents_path:, directory:)
        cache_directory_to_discovery_json_reader[directory] ||= begin
          discovery_json_reader = discovery_json_reader(repo_contents_path: repo_contents_path,
                                                        workspace_path: directory)
          cache_directory_to_discovery_json_reader[directory] = discovery_json_reader
          dependency_file_cache_key = cache_key_from_dependency_file_paths(discovery_json_reader.dependency_file_paths)
          cache_dependency_file_paths_to_discovery_json_reader[dependency_file_cache_key] = discovery_json_reader
          discovery_file_path = discovery_file_path_from_workspace_path(directory)
          cache_dependency_file_paths_to_discovery_json_path[dependency_file_cache_key] = discovery_file_path

          discovery_json_reader
        end
      end

      # Retrieves the cached NativeDiscoveryJsonReader object for the given dependency file paths.
      sig { params(dependency_file_paths: T::Array[String]).returns(NativeDiscoveryJsonReader) }
      def self.load_discovery_for_dependency_file_paths(dependency_file_paths)
        dependency_file_cache_key = cache_key_from_dependency_file_paths(dependency_file_paths)
        T.must(cache_dependency_file_paths_to_discovery_json_reader[dependency_file_cache_key])
      end

      # Retrieves the cached location of the discovery JSON file for the given dependency file paths.
      sig { params(dependency_file_paths: T::Array[String]).returns(String) }
      def self.get_discovery_json_path_for_dependency_file_paths(dependency_file_paths)
        dependency_file_cache_key = cache_key_from_dependency_file_paths(dependency_file_paths)
        T.must(cache_dependency_file_paths_to_discovery_json_path[dependency_file_cache_key])
      end

      sig { params(repo_contents_path: String, dependency_file: Dependabot::DependencyFile).returns(String) }
      def self.dependency_file_path(repo_contents_path:, dependency_file:)
        dep_file_path = Pathname.new(File.join(dependency_file.directory, dependency_file.name)).cleanpath.to_path
        dep_file_path.delete_prefix("#{repo_contents_path}/")
      end

      sig { returns(String) }
      def self.discovery_map_file_path
        File.join(discovery_directory, "discovery_map.json")
      end

      sig { params(workspace_path: String).returns(String) }
      def self.discovery_file_path_from_workspace_path(workspace_path)
        # Given an update directory (also known as a workspace path), this function returns the path where the discovery
        # JSON file is located.  This function is called both by methods that need to write the discovery JSON file and
        # by methods that need to read the discovery JSON file.  This function is also called by multiple processes so
        # we need a way to retain the data.  This is accomplished by the following steps:
        #  1. Check a well-known file for a mapping of workspace_path => discovery file path.  If found, return it.
        #  2. If the path is not found, generate a new path, save it to the well-known file, and return the value.
        discovery_map_contents = File.exist?(discovery_map_file_path) ? File.read(discovery_map_file_path) : "{}"
        discovery_map = T.let(JSON.parse(discovery_map_contents), T::Hash[String, String])

        discovery_json_path = discovery_map[workspace_path]
        if discovery_json_path
          Dependabot.logger.info("Discovery JSON path for workspace path [#{workspace_path}] found in file " \
                                 "[#{discovery_map_file_path}] at location [#{discovery_json_path}]")
          return discovery_json_path
        end

        # no discovery JSON path found; generate a new one, but first find a suitable location
        discovery_json_counter = 1
        new_discovery_json_path = ""
        loop do
          new_discovery_json_path = File.join(discovery_directory, "discovery.#{discovery_json_counter}.json")
          break unless File.exist?(new_discovery_json_path)

          discovery_json_counter += 1
        end

        discovery_map[workspace_path] = new_discovery_json_path

        File.write(discovery_map_file_path, discovery_map.to_json)
        Dependabot.logger.info("Discovery JSON path for workspace path [#{workspace_path}] created for file " \
                               "[#{discovery_map_file_path}] at location [#{new_discovery_json_path}]")
        new_discovery_json_path
      end

      sig { params(dependency_file_paths: T::Array[String]).returns(String) }
      def self.cache_key_from_dependency_file_paths(dependency_file_paths)
        dependency_file_paths.sort.join(",")
      end

      sig { returns(String) }
      def self.discovery_directory
        t = File.join(Dir.home, ".dependabot")
        FileUtils.mkdir_p(t)
        t
      end

      sig { params(repo_contents_path: String, workspace_path: String).returns(NativeDiscoveryJsonReader) }
      def self.discovery_json_reader(repo_contents_path:, workspace_path:)
        discovery_file_path = discovery_file_path_from_workspace_path(workspace_path)
        discovery_json = DependencyFile.new(
          name: Pathname.new(discovery_file_path).cleanpath.to_path,
          directory: discovery_directory,
          type: "file",
          content: File.read(discovery_file_path)
        )
        NativeDiscoveryJsonReader.new(repo_contents_path: repo_contents_path, discovery_json: discovery_json)
      end

      sig { returns(T.nilable(NativeWorkspaceDiscovery)) }
      attr_reader :workspace_discovery

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      attr_reader :dependency_set

      sig { returns(T::Array[String]) }
      attr_reader :dependency_file_paths

      sig { params(repo_contents_path: String, discovery_json: DependencyFile).void }
      def initialize(repo_contents_path:, discovery_json:)
        @repo_contents_path = repo_contents_path
        @discovery_json = discovery_json
        @workspace_discovery = T.let(read_workspace_discovery, T.nilable(Dependabot::Nuget::NativeWorkspaceDiscovery))
        @dependency_set = T.let(read_dependency_set, Dependabot::FileParsers::Base::DependencySet)
        @dependency_file_paths = T.let(read_dependency_file_paths, T::Array[String])
      end

      private

      sig { returns(String) }
      attr_reader :repo_contents_path

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

      sig { returns(T::Array[String]) }
      def read_dependency_file_paths
        dependency_file_paths = T.let([], T::Array[T.nilable(String)])
        dependency_file_paths << dependency_file_path_from_repo_path("global.json") if workspace_discovery&.global_json
        if workspace_discovery&.dotnet_tools_json
          dependency_file_paths << dependency_file_path_from_repo_path(".config/dotnet-tools.json")
        end

        projects = workspace_discovery&.projects || []
        projects.each do |project|
          dependency_file_paths << dependency_file_path_from_repo_path(project.file_path)
          dependency_file_paths += project.imported_files.map do |f|
            dependency_file_path_from_project_path(project.file_path, f)
          end
          dependency_file_paths += project.additional_files.map do |f|
            dependency_file_path_from_project_path(project.file_path, f)
          end
        end

        deduped_dependency_file_paths = T.let(Set.new(dependency_file_paths.compact), T::Set[String])
        result = deduped_dependency_file_paths.sort
        result
      end

      sig { params(path_parts: String).returns(T.nilable(String)) }
      def dependency_file_path_from_repo_path(*path_parts)
        path_parts = path_parts.map { |p| p.delete_prefix("/").delete_suffix("/") }
        normalized_repo_path = Pathname.new(path_parts.join("/")).cleanpath.to_path.delete_prefix("/")
        full_path = Pathname.new(File.join(repo_contents_path, normalized_repo_path)).cleanpath.to_path
        return unless File.exist?(full_path)

        normalized_repo_path = "/#{normalized_repo_path}" unless normalized_repo_path.start_with?("/")
        normalized_repo_path
      end

      sig { params(project_path: String, relative_file_path: String).returns(T.nilable(String)) }
      def dependency_file_path_from_project_path(project_path, relative_file_path)
        project_directory = File.dirname(project_path)
        dependency_file_path_from_repo_path(project_directory, relative_file_path)
      end
    end
  end
end
