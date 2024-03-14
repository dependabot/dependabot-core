# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/discovery/dependency_details"

module Dependabot
  module Nuget
    class DependencyFileDiscovery
      extend T::Sig

      sig { params(json: T.nilable(T::Hash[String, T.untyped])).returns(T.nilable(DependencyFileDiscovery)) }
      def self.from_json(json)
        return nil if json.nil?

        file_path = T.let(json.fetch("FilePath"), String)
        dependencies = T.let(json.fetch("Dependencies"), T::Array[T::Hash[String, T.untyped]]).map do |dep|
          DependencyDetails.from_json(dep)
        end

        DependencyFileDiscovery.new(file_path: file_path,
                                    dependencies: dependencies)
      end

      sig do
        params(file_path: String,
               dependencies: T::Array[DependencyDetails]).void
      end
      def initialize(file_path:, dependencies:)
        @file_path = file_path
        @dependencies = dependencies
      end

      sig { returns(String) }
      attr_reader :file_path

      sig { returns(T::Array[DependencyDetails]) }
      attr_reader :dependencies

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def dependency_set
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        file_name = Pathname.new(file_path).cleanpath.to_path
        dependencies.each do |dependency_details|
          # Exclude any dependencies using version ranges or wildcards
          next if dependency_details.version == "" ||
                  dependency_details.version.include?(",") ||
                  dependency_details.version.include?("*")

          # Exclude any dependencies specified using interpolation
          next if dependency_details.name.include?("%(") ||
                  dependency_details.version.include?("%(")

          # Exclude any dependencies that are updates
          next if dependency_details.is_update

          dependency_set << build_dependency(file_name, dependency_details)
        end

        dependency_set
      end

      private

      sig { params(file_name: String, dependency_details: DependencyDetails).returns(Dependabot::Dependency) }
      def build_dependency(file_name, dependency_details)
        requirement = build_requirement(file_name, dependency_details)
        requirements = requirement.nil? ? [] : [requirement]

        version = dependency_details.version.gsub(/[\(\)\[\]]/, "").strip

        Dependency.new(
          name: dependency_details.name,
          version: version,
          package_manager: "nuget",
          requirements: requirements
        )
      end

      sig do
        params(file_name: String, dependency_details: DependencyDetails)
          .returns(T.nilable(T::Hash[Symbol, T.untyped]))
      end
      def build_requirement(file_name, dependency_details)
        return if dependency_details.is_transitive

        requirement = {
          requirement: dependency_details.version,
          file: file_name,
          groups: [dependency_details.is_dev_dependency ? "devDependencies" : "dependencies"],
          source: nil
        }

        property_name = dependency_details.evaluation&.last_property_name
        return requirement unless property_name

        requirement[:metadata] = { property_name: property_name }
        requirement
      end
    end
  end
end
