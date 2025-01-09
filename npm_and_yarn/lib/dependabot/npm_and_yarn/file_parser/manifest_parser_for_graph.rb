# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/helpers"
require "json"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class ManifestParserForGraph
      extend T::Sig

      DEPENDENCY_TYPES = T.let(%w(dependencies devDependencies optionalDependencies).freeze, T::Array[String])

      sig { params(package_files: T::Array[DependencyFile]).void }
      def initialize(package_files)
        @package_files = package_files
      end

      sig { returns(T::Hash[String, Dependabot::Dependency]) }
      def parse
        dependencies = T.let({}, T::Hash[String, Dependabot::Dependency])

        @package_files.each do |file|
          json = JSON.parse(T.must(file.content))

          # Skip flat dependencies (unsupported structures)
          next if json["flat"]

          self.class.each_dependency(json) do |name, requirement, type|
            next unless requirement.is_a?(String)

            # Skip Yarn workspace cross-references
            next if requirement.start_with?("workspace:")

            # Normalize empty requirements
            requirement = "*" if requirement.empty?

            # Find version from manifest

            # Create and store the dependency
            dependencies[name] = Dependabot::Dependency.new(
              name: name,
              version: nil, # No explicit version in the manifest
              package_manager: ECOSYSTEM,
              requirements: [{
                requirement: requirement,
                file: file.name,
                groups: [type],
                source: nil
              }]
            )
          end
        end

        dependencies
      end

      sig do
        params(
          json: T::Hash[String, T.untyped],
          block: T.proc.params(name: String, requirement: String, type: String).void
        ).void
      end
      def self.each_dependency(json, &block)
        DEPENDENCY_TYPES.each do |type|
          deps = json[type] || {}
          deps.each(&block)
        end
      end
    end
  end
end
