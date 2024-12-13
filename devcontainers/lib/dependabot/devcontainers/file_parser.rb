# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/devcontainers/version"
require "dependabot/devcontainers/language"
require "dependabot/devcontainers/package_manager"
require "dependabot/devcontainers/file_parser/feature_dependency_parser"

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
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(begin
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          )
        end, T.nilable(Dependabot::Ecosystem))
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

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def config_dependency_files
        @config_dependency_files ||= T.let(
          dependency_files.select do |f|
            f.name.end_with?("devcontainer.json")
          end,
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(devcontainer_version)),
          T.nilable(Dependabot::Devcontainers::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          Language.new(T.must(node_version)),
          T.nilable(Dependabot::Devcontainers::Language)
        )
      end

      sig { returns(T.nilable(String)) }
      def devcontainer_version
        @devcontainer_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("devcontainer --version")
            version.match(Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN)&.captures&.first
          end,
          T.nilable(String)
        )
      end

      sig { returns(T.nilable(String)) }
      def node_version
        @node_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("node --version")
            version.match(Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN)&.captures&.first
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("devcontainers", Dependabot::Devcontainers::FileParser)
