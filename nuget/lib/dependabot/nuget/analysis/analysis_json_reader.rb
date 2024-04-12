# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/nuget/discovery/discovery_json_reader"
require "json"
require "sorbet-runtime"

module Dependabot
  module Nuget
    class AnalysisJsonReader
      extend T::Sig

      sig { returns(String) }
      def self.temp_directory
        File.join(DiscoveryJsonReader.temp_directory, "analysis")
      end

      sig { params(dependency_name: String).returns(String) }
      def self.analysis_file_path(dependency_name:)
        File.join(temp_directory, "#{dependency_name}.json")
      end

      sig { params(dependency_name: String).returns(T.nilable(DependencyFile)) }
      def self.analysis_json(dependency_name:)
        file_path = analysis_file_path(dependency_name: dependency_name)
        return unless File.exist?(file_path)

        DependencyFile.new(
          name: Pathname.new(file_path).cleanpath.to_path,
          directory: temp_directory,
          type: "file",
          content: File.read(file_path)
        )
      end

      sig { params(analysis_json: DependencyFile).void }
      def initialize(analysis_json:)
        @analysis_json = analysis_json
      end

      sig { returns(Dependabot::Nuget::Version) }
      def updated_version
        Version.new("1.0.0")
      end

      sig { returns(T::Boolean) }
      def can_update?
        true
      end

      sig { returns(T::Boolean) }
      def version_comes_from_multi_dependency_property?
        false
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies
        []
      end
    end
  end
end
