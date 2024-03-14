# typed: strong
# frozen_string_literal: true

require "dependabot/nuget/discovery/discovery_json_reader"

module Dependabot
  module Nuget
    class TfmFinder
      extend T::Sig

      sig { params(dependency: Dependency).returns(T::Array[String]) }
      def self.frameworks(dependency)
        discovery_json = DiscoveryJsonReader.discovery_json
        return [] unless discovery_json

        workspace = DiscoveryJsonReader.new(
          discovery_json: discovery_json
        ).workspace_discovery
        return [] unless workspace

        workspace.projects.select do |project|
          project.dependencies.any? { |d| d.name.casecmp?(dependency.name) }
        end.flat_map(&:target_frameworks).uniq
      end
    end
  end
end
