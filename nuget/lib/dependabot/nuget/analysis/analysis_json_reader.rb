# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/nuget/analysis/dependency_analysis"
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

      sig { returns(DependencyAnalysis) }
      def dependency_analysis
        @dependency_analysis ||= T.let(begin
          raise Dependabot::DependencyFileNotParseable, analysis_json.path unless analysis_json.content

          Dependabot.logger.info("#{File.basename(analysis_json.path)} analysis content: #{analysis_json.content}")
          puts "#{File.basename(analysis_json.path)} analysis content: #{analysis_json.content}"

          parsed_json = T.let(JSON.parse(T.must(analysis_json.content)), T::Hash[String, T.untyped])
          DependencyAnalysis.from_json(parsed_json)
        end, T.nilable(DependencyAnalysis))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, analysis_json.path
      end

      private

      sig { returns(DependencyFile) }
      attr_reader :analysis_json
    end
  end
end
