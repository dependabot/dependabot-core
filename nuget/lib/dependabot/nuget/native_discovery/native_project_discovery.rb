# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/native_discovery/native_dependency_details"
require "dependabot/nuget/native_discovery/native_property_details"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class NativeProjectDiscovery < NativeDependencyFileDiscovery
      extend T::Sig

      sig do
        override.params(json: T.nilable(T::Hash[String, T.untyped]),
                        directory: String).returns(T.nilable(NativeProjectDiscovery))
      end
      def self.from_json(json, directory)
        return nil if json.nil?

        file_path = File.join(directory, T.let(json.fetch("FilePath"), String))
        properties = T.let(json.fetch("Properties"), T::Array[T::Hash[String, T.untyped]]).map do |prop|
          NativePropertyDetails.from_json(prop)
        end
        target_frameworks = T.let(json.fetch("TargetFrameworks"), T::Array[String])
        referenced_project_paths = T.let(json.fetch("ReferencedProjectPaths"), T::Array[String])
        dependencies = T.let(json.fetch("Dependencies"), T::Array[T::Hash[String, T.untyped]]).filter_map do |dep|
          details = NativeDependencyDetails.from_json(dep)
          next unless details.version # can't do anything without a version

          version = T.must(details.version)
          next unless version.length.positive? # can't do anything with an empty version

          next if version.include? "," # can't do anything with a range

          next if version.include? "*" # can't do anything with a wildcard

          details
        end

        NativeProjectDiscovery.new(file_path: file_path,
                                   properties: properties,
                                   target_frameworks: target_frameworks,
                                   referenced_project_paths: referenced_project_paths,
                                   dependencies: dependencies)
      end

      sig do
        params(file_path: String,
               properties: T::Array[NativePropertyDetails],
               target_frameworks: T::Array[String],
               referenced_project_paths: T::Array[String],
               dependencies: T::Array[NativeDependencyDetails]).void
      end
      def initialize(file_path:, properties:, target_frameworks:, referenced_project_paths:, dependencies:)
        super(file_path: file_path, dependencies: dependencies)
        @properties = properties
        @target_frameworks = target_frameworks
        @referenced_project_paths = referenced_project_paths
      end

      sig { returns(T::Array[NativePropertyDetails]) }
      attr_reader :properties

      sig { returns(T::Array[String]) }
      attr_reader :target_frameworks

      sig { returns(T::Array[String]) }
      attr_reader :referenced_project_paths

      sig { override.returns(Dependabot::FileParsers::Base::DependencySet) }
      def dependency_set
        if target_frameworks.empty? && file_path.end_with?("proj")
          Dependabot.logger.warn("Excluding project file '#{file_path}' due to unresolvable target framework")
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new
          return dependency_set
        end

        super
      end
    end
  end
end
