# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/discovery/dependency_file_discovery"
require "dependabot/nuget/discovery/directory_packages_props_discovery"
require "dependabot/nuget/discovery/project_discovery"

module Dependabot
  module Nuget
    class WorkspaceDiscovery
      extend T::Sig

      sig { params(json: T::Hash[String, T.untyped]).returns(WorkspaceDiscovery) }
      def self.from_json(json)
        file_path = T.let(json.fetch("FilePath"), String)
        type = T.let(json.fetch("Type"), String)
        target_frameworks = T.let(json.fetch("TargetFrameworks"), T::Array[String])
        projects = T.let(json.fetch("Projects"), T::Array[T::Hash[String, T.untyped]]).filter_map do |project|
          ProjectDiscovery.from_json(project)
        end
        directory_packages_props = DirectoryPackagesPropsDiscovery
                                   .from_json(T.let(json.fetch("DirectoryPackagesProps"),
                                                    T.nilable(T::Hash[String, T.untyped])))
        global_json = DependencyFileDiscovery
                      .from_json(T.let(json.fetch("GlobalJson"), T.nilable(T::Hash[String, T.untyped])))
        dotnet_tools_json = DependencyFileDiscovery
                            .from_json(T.let(json.fetch("DotNetToolsJson"), T.nilable(T::Hash[String, T.untyped])))

        WorkspaceDiscovery.new(file_path: file_path,
                               type: type,
                               target_frameworks: target_frameworks,
                               projects: projects,
                               directory_packages_props: directory_packages_props,
                               global_json: global_json,
                               dotnet_tools_json: dotnet_tools_json)
      end

      sig do
        params(file_path: String,
               type: String,
               target_frameworks: T::Array[String],
               projects: T::Array[ProjectDiscovery],
               directory_packages_props: T.nilable(DirectoryPackagesPropsDiscovery),
               global_json: T.nilable(DependencyFileDiscovery),
               dotnet_tools_json: T.nilable(DependencyFileDiscovery)).void
      end
      def initialize(file_path:, type:, target_frameworks:, projects:, directory_packages_props:, global_json:,
                     dotnet_tools_json:)
        @file_path = file_path
        @type = type
        @target_frameworks = target_frameworks
        @projects = projects
        @directory_packages_props = directory_packages_props
        @global_json = global_json
        @dotnet_tools_json = dotnet_tools_json
      end

      sig { returns(String) }
      attr_reader :file_path

      sig { returns(String) }
      attr_reader :type

      sig { returns(T::Array[String]) }
      attr_reader :target_frameworks

      sig { returns(T::Array[ProjectDiscovery]) }
      attr_reader :projects

      sig { returns(T.nilable(DirectoryPackagesPropsDiscovery)) }
      attr_reader :directory_packages_props

      sig { returns(T.nilable(DependencyFileDiscovery)) }
      attr_reader :global_json

      sig { returns(T.nilable(DependencyFileDiscovery)) }
      attr_reader :dotnet_tools_json
    end
  end
end
