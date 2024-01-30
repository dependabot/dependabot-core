# typed: true
# frozen_string_literal: true

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/devcontainers/version"
require "dependabot/devcontainers/file_parser/feature_dependency_parser"

module Dependabot
  module Devcontainers
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new

        config_dependency_files.each do |config_dependency_file|
          parse_features(config_dependency_file).each do |dep|
            dependency_set << dep
          end
        end

        dependency_set.dependencies
      end

      private

      def check_required_files
        return if config_dependency_files.any?

        raise "No dev container configuration!"
      end

      def parse_features(config_dependency_file)
        FeatureDependencyParser.new(
          config_dependency_file: config_dependency_file,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        ).parse
      end

      def config_dependency_files
        @config_dependency_files ||= dependency_files.select do |f|
          f.name.end_with?("devcontainer.json")
        end
      end
    end
  end
end

Dependabot::FileParsers.register("devcontainers", Dependabot::Devcontainers::FileParser)
