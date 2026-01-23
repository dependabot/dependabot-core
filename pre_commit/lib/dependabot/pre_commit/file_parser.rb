# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "dependabot/pre_commit/package_manager"
require "dependabot/pre_commit/version"
require "dependabot/pre_commit/requirement"

module Dependabot
  module PreCommit
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      CONFIG_FILE_PATTERN = /\.pre-commit(-config)?\.ya?ml$/i
      ECOSYSTEM = "pre_commit"

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Ecosystem)
        )
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        pre_commit_config_files.each do |file|
          dependency_set += parse_config_file(file)
        end

        dependency_set.dependencies
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::PreCommit::PackageManager))
      end

      sig { params(file: Dependabot::DependencyFile).returns(DependencySet) }
      def parse_config_file(file)
        dependency_set = DependencySet.new

        yaml = YAML.safe_load(T.must(file.content), aliases: true)
        return dependency_set unless yaml.is_a?(Hash)

        repos = yaml.fetch("repos", [])
        repos.each do |repo|
          next unless repo.is_a?(Hash)

          dependency = parse_repo(repo, file)
          dependency_set << dependency if dependency
        end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias => e
        raise Dependabot::DependencyFileNotParseable.new(file.path, e.message)
      end

      sig do
        params(
          repo: T::Hash[String, T.untyped],
          file: Dependabot::DependencyFile
        ).returns(T.nilable(Dependency))
      end
      def parse_repo(repo, file)
        repo_url = repo["repo"]
        rev = repo["rev"]

        return nil if repo_url.nil? || rev.nil?
        return nil if repo_url == "local"

        Dependency.new(
          name: repo_url,
          version: rev,
          requirements: [{
            requirement: nil,
            groups: [],
            file: file.name,
            source: {
              type: "git",
              url: repo_url,
              ref: rev,
              branch: nil
            }
          }],
          package_manager: ECOSYSTEM
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pre_commit_config_files
        dependency_files.select { |f| f.name.match?(CONFIG_FILE_PATTERN) }
      end

      sig { override.void }
      def check_required_files
        return if pre_commit_config_files.any?

        raise "No pre-commit configuration file found!"
      end
    end
  end
end

Dependabot::FileParsers.register("pre_commit", Dependabot::PreCommit::FileParser)
