# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/discovery/dependency_details"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class DependencyFileDiscovery
      extend T::Sig

      sig do
        params(json: T.nilable(T::Hash[String, T.untyped]),
               directory: String).returns(T.nilable(DependencyFileDiscovery))
      end
      def self.from_json(json, directory)
        return nil if json.nil?

        file_path = File.join(directory, T.let(json.fetch("FilePath"), String))
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

      sig { overridable.returns(Dependabot::FileParsers::Base::DependencySet) }
      def dependency_set # rubocop:disable Metrics/PerceivedComplexity
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        file_name = Pathname.new(file_path).cleanpath.to_path
        dependencies.each do |dependency|
          next if dependency.name.casecmp("Microsoft.NET.Sdk")&.zero?

          # If the version string was evaluated it must have been successfully resolved
          if dependency.evaluation && dependency.evaluation&.result_type != "Success"
            logger.warn "Dependency '#{dependency.name}' excluded due to unparsable version: #{dependency.version}"
            next
          end

          # Exclude any dependencies using version ranges or wildcards
          next if dependency.version&.include?(",") ||
                  dependency.version&.include?("*")

          # Exclude any dependencies specified using interpolation
          next if dependency.name.include?("%(") ||
                  dependency.version&.include?("%(")

          # Exclude any dependencies which reference an item type
          next if dependency.name.include?("@(")

          dependency_set << build_dependency(file_name, dependency)
        end

        dependency_set
      end

      private

      sig { returns(::Logger) }
      def logger
        Dependabot.logger
      end

      sig { params(file_name: String, dependency_details: DependencyDetails).returns(Dependabot::Dependency) }
      def build_dependency(file_name, dependency_details)
        requirement = build_requirement(file_name, dependency_details)
        requirements = requirement.nil? ? [] : [requirement]

        version = dependency_details.version&.gsub(/[\(\)\[\]]/, "")&.strip
        version = nil if version&.empty?

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

        version = dependency_details.version
        version = nil if version&.empty?

        requirement = {
          requirement: version,
          file: file_name,
          groups: [dependency_details.is_dev_dependency ? "devDependencies" : "dependencies"],
          source: nil
        }

        property_name = dependency_details.evaluation&.root_property_name
        return requirement unless property_name

        requirement[:metadata] = { property_name: property_name }
        requirement
      end
    end
  end
end
