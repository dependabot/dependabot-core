# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/discovery/dependency_file_discovery"
require "dependabot/nuget/discovery/project_discovery"
require "dependabot/nuget/native_helpers"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class WorkspaceDiscovery
      extend T::Sig

      sig { params(json: T::Hash[String, T.untyped]).returns(WorkspaceDiscovery) }
      def self.from_json(json)
        Dependabot::Nuget::NativeHelpers.ensure_no_errors(json)

        path = T.let(json.fetch("Path"), String)
        path = "/" + path unless path.start_with?("/")
        projects = T.let(json.fetch("Projects"), T::Array[T::Hash[String, T.untyped]]).filter_map do |project|
          ProjectDiscovery.from_json(project, path)
        end
        global_json = DependencyFileDiscovery
                      .from_json(T.let(json.fetch("GlobalJson"), T.nilable(T::Hash[String, T.untyped])), path)
        dotnet_tools_json = DependencyFileDiscovery
                            .from_json(T.let(json.fetch("DotNetToolsJson"),
                                             T.nilable(T::Hash[String, T.untyped])), path)

        WorkspaceDiscovery.new(path: path,
                               projects: projects,
                               global_json: global_json,
                               dotnet_tools_json: dotnet_tools_json)
      end

      sig do
        params(path: String,
               projects: T::Array[ProjectDiscovery],
               global_json: T.nilable(DependencyFileDiscovery),
               dotnet_tools_json: T.nilable(DependencyFileDiscovery)).void
      end
      def initialize(path:, projects:, global_json:, dotnet_tools_json:)
        @path = path
        @projects = projects
        @global_json = global_json
        @dotnet_tools_json = dotnet_tools_json
      end

      sig { returns(String) }
      attr_reader :path

      sig { returns(T::Array[ProjectDiscovery]) }
      attr_reader :projects

      sig { returns(T.nilable(DependencyFileDiscovery)) }
      attr_reader :global_json

      sig { returns(T.nilable(DependencyFileDiscovery)) }
      attr_reader :dotnet_tools_json
    end
  end
end
