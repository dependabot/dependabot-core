# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/native_discovery/native_dependency_file_discovery"
require "dependabot/nuget/native_discovery/native_project_discovery"
require "dependabot/nuget/native_helpers"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeWorkspaceDiscovery
      extend T::Sig

      sig { params(json: T::Hash[String, T.untyped]).returns(NativeWorkspaceDiscovery) }
      def self.from_json(json)
        Dependabot::Nuget::NativeHelpers.ensure_no_errors(json)

        path = T.let(json.fetch("Path"), String)
        path = "/" + path unless path.start_with?("/")
        projects = T.let(json.fetch("Projects"), T::Array[T::Hash[String, T.untyped]]).filter_map do |project|
          NativeProjectDiscovery.from_json(project, path)
        end
        global_json = NativeDependencyFileDiscovery
                      .from_json(T.let(json.fetch("GlobalJson"), T.nilable(T::Hash[String, T.untyped])), path)
        dotnet_tools_json = NativeDependencyFileDiscovery
                            .from_json(T.let(json.fetch("DotNetToolsJson"),
                                             T.nilable(T::Hash[String, T.untyped])), path)

        NativeWorkspaceDiscovery.new(path: path,
                                     projects: projects,
                                     global_json: global_json,
                                     dotnet_tools_json: dotnet_tools_json)
      end

      sig do
        params(path: String,
               projects: T::Array[NativeProjectDiscovery],
               global_json: T.nilable(NativeDependencyFileDiscovery),
               dotnet_tools_json: T.nilable(NativeDependencyFileDiscovery)).void
      end
      def initialize(path:, projects:, global_json:, dotnet_tools_json:)
        @path = path
        @projects = projects
        @global_json = global_json
        @dotnet_tools_json = dotnet_tools_json
      end

      sig { returns(String) }
      attr_reader :path

      sig { returns(T::Array[NativeProjectDiscovery]) }
      attr_reader :projects

      sig { returns(T.nilable(NativeDependencyFileDiscovery)) }
      attr_reader :global_json

      sig { returns(T.nilable(NativeDependencyFileDiscovery)) }
      attr_reader :dotnet_tools_json
    end
  end
end
