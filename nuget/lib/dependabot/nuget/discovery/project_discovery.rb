# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/discovery/dependency_details"
require "dependabot/nuget/discovery/property_details"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class ProjectDiscovery < DependencyFileDiscovery
      extend T::Sig

      sig do
        params(json: T.nilable(T::Hash[String, T.untyped])).returns(T.nilable(ProjectDiscovery))
      end
      def self.from_json(json)
        return nil if json.nil?

        file_path = T.let(json.fetch("FilePath"), String)
        properties = T.let(json.fetch("Properties"), T::Array[T::Hash[String, T.untyped]]).map do |prop|
          PropertyDetails.from_json(prop)
        end
        target_frameworks = T.let(json.fetch("TargetFrameworks"), T::Array[String])
        referenced_project_paths = T.let(json.fetch("ReferencedProjectPaths"), T::Array[String])
        dependencies = T.let(json.fetch("Dependencies"), T::Array[T::Hash[String, T.untyped]]).map do |dep|
          DependencyDetails.from_json(dep)
        end

        ProjectDiscovery.new(file_path: file_path,
                             properties: properties,
                             target_frameworks: target_frameworks,
                             referenced_project_paths: referenced_project_paths,
                             dependencies: dependencies)
      end

      sig do
        params(file_path: String,
               properties: T::Array[PropertyDetails],
               target_frameworks: T::Array[String],
               referenced_project_paths: T::Array[String],
               dependencies: T::Array[DependencyDetails]).void
      end
      def initialize(file_path:, properties:, target_frameworks:, referenced_project_paths:, dependencies:)
        super(file_path: file_path, dependencies: dependencies)
        @properties = properties
        @target_frameworks = target_frameworks
        @referenced_project_paths = referenced_project_paths
      end

      sig { returns(T::Array[PropertyDetails]) }
      attr_reader :properties

      sig { returns(T::Array[String]) }
      attr_reader :target_frameworks

      sig { returns(T::Array[String]) }
      attr_reader :referenced_project_paths
    end
  end
end
