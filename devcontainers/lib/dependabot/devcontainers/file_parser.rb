# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/devcontainers/version"
require "dependabot/devcontainers/file_parser/feature_dependency_parser"
require "dependabot/devcontainers/file_parser/image_dependency_parser"

module Dependabot
  module Devcontainers
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        config_dependency_files.each do |config_dependency_file|
          parse_features(config_dependency_file).each do |dep|
            dependency_set << dep
          end
          parse_images(config_dependency_file).each do |dep|
            dependency_set << dep
          end
        end

        dependency_set.dependencies
      end

      private

      sig { override.void }
      def check_required_files
        return if config_dependency_files.any?

        raise "No dev container configuration!"
      end

      sig { params(config_dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_features(config_dependency_file)
        FeatureDependencyParser.new(
          config_dependency_file: config_dependency_file,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        ).parse
      end

      sig { params(config_dependency_file: Dependabot::DependencyFile).returns(T::Array[Dependabot::Dependency]) }
      def parse_images(config_dependency_file)
        ImageDependencyParser.new(
          config_dependency_file: config_dependency_file,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        ).parse
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def config_dependency_files
        @config_dependency_files ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("devcontainer.json")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end
    end
  end
end

Dependabot::FileParsers.register("devcontainers", Dependabot::Devcontainers::FileParser)
