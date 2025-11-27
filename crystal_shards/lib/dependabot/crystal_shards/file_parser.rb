# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"
require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/crystal_shards/requirement"
require "dependabot/crystal_shards/language"
require "dependabot/crystal_shards/package_manager"

module Dependabot
  module CrystalShards
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_TYPES = %w(dependencies development_dependencies).freeze
      VALID_SHARD_NAME = /\A[a-zA-Z0-9_-]+\z/
      VALID_GITHUB_SHORTHAND = %r{\A[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\z}
      DEFAULT_CRYSTAL_VERSION = "1.15.0"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_set += shard_yml_dependencies if shard_yml

        dependency_set.dependencies.sort_by(&:name)
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(DEFAULT_SHARDS_VERSION),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          Language.new(detected_crystal_version),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(String) }
      def detected_crystal_version
        crystal_version_file = get_original_file(".crystal-version")
        content = crystal_version_file&.content
        if content
          version = content.strip
          return version if version.match?(/\A\d+\.\d+(\.\d+)?\z/)
        end

        crystal_req = parsed_shard_yml["crystal"]
        if crystal_req.is_a?(String) && crystal_req.match?(/\d+\.\d+/)
          match = crystal_req.match(/(\d+\.\d+(\.\d+)?)/)
          return T.must(match[1]) if match
        end

        DEFAULT_CRYSTAL_VERSION
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def shard_yml_dependencies
        dependency_set = DependencySet.new

        DEPENDENCY_TYPES.each do |dep_type|
          deps = parsed_shard_yml.fetch(dep_type, {})
          next unless deps.is_a?(Hash)

          deps.each do |name, details|
            next unless details.is_a?(Hash)
            next unless valid_dependency_name?(name)

            dependency_set << build_shard_dependency(
              name: name,
              group: dep_type,
              details: details
            )
          end
        end

        dependency_set
      end

      sig { params(name: T.untyped).returns(T::Boolean) }
      def valid_dependency_name?(name)
        return false unless name.is_a?(String)
        return false if name.empty? || name.length > 100

        VALID_SHARD_NAME.match?(name)
      end

      sig do
        params(
          name: String,
          group: String,
          details: T::Hash[String, T.untyped]
        ).returns(Dependabot::Dependency)
      end
      def build_shard_dependency(name:, group:, details:)
        source = extract_source(details)
        requirement_string = extract_requirement(details)

        requirements = [{
          requirement: requirement_string,
          groups: [group],
          source: source,
          file: MANIFEST_FILE
        }]

        version = locked_version(name) || extract_version_from_requirement(requirement_string)

        Dependency.new(
          name: name,
          version: version&.to_s,
          requirements: requirements,
          package_manager: "crystal_shards"
        )
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def extract_requirement(details)
        version = details["version"]
        return nil unless version.is_a?(String)

        version
      end

      sig { params(requirement: T.nilable(String)).returns(T.nilable(String)) }
      def extract_version_from_requirement(requirement)
        return nil unless requirement.is_a?(String)

        match = requirement.match(/(\d+\.\d+(\.\d+)?)/)
        match ? match[1] : nil
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def extract_source(details)
        if details["github"]
          extract_github_source(details)
        elsif details["gitlab"]
          extract_gitlab_source(details)
        elsif details["bitbucket"]
          extract_bitbucket_source(details)
        elsif details["git"]
          extract_git_source(details)
        elsif details["path"]
          extract_path_source(details)
        end
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def extract_github_source(details)
        shorthand = details["github"]
        return nil unless shorthand.is_a?(String)
        return nil unless VALID_GITHUB_SHORTHAND.match?(shorthand)

        {
          type: "git",
          url: "https://github.com/#{shorthand}",
          branch: details["branch"],
          ref: details["tag"] || details["commit"]
        }
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def extract_gitlab_source(details)
        shorthand = details["gitlab"]
        return nil unless shorthand.is_a?(String)
        return nil unless VALID_GITHUB_SHORTHAND.match?(shorthand)

        {
          type: "git",
          url: "https://gitlab.com/#{shorthand}",
          branch: details["branch"],
          ref: details["tag"] || details["commit"]
        }
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def extract_bitbucket_source(details)
        shorthand = details["bitbucket"]
        return nil unless shorthand.is_a?(String)
        return nil unless VALID_GITHUB_SHORTHAND.match?(shorthand)

        {
          type: "git",
          url: "https://bitbucket.org/#{shorthand}",
          branch: details["branch"],
          ref: details["tag"] || details["commit"]
        }
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def extract_git_source(details)
        url = details["git"]
        return nil unless url.is_a?(String)
        return nil unless valid_git_url?(url)

        {
          type: "git",
          url: url,
          branch: details["branch"],
          ref: details["tag"] || details["commit"]
        }
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def extract_path_source(details)
        path = details["path"]
        return nil unless path.is_a?(String)

        {
          type: "path",
          path: path
        }
      end

      sig { params(url: String).returns(T::Boolean) }
      def valid_git_url?(url)
        return false if url.empty? || url.length > 500

        url.match?(%r{\A(https?://|git://|ssh://|git@)}) ||
          url.match?(/\A[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+:/)
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def locked_version(name)
        lock = shard_lock
        return nil unless lock

        content = lock.content
        return nil unless content

        parsed_lock = YAML.safe_load(content)
        return nil unless parsed_lock.is_a?(Hash)

        shards = parsed_lock.fetch("shards", {})
        return nil unless shards.is_a?(Hash)

        version = shards.dig(name, "version")
        version.is_a?(String) ? version : nil
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias => e
        raise Dependabot::DependencyFileNotParseable,
              "#{LOCKFILE}: #{e.message}"
      end

      sig { override.void }
      def check_required_files
        return if shard_yml

        raise "No #{MANIFEST_FILE}"
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_shard_yml
        @parsed_shard_yml ||= T.let(
          begin
            content = shard_yml&.content
            raise Dependabot::DependencyFileNotParseable, MANIFEST_FILE unless content

            result = YAML.safe_load(content)
            raise Dependabot::DependencyFileNotParseable, MANIFEST_FILE unless result.is_a?(Hash)

            result
          end,
          T.nilable(T::Hash[String, T.untyped])
        )
      rescue Psych::SyntaxError
        raise Dependabot::DependencyFileNotParseable, shard_yml&.path || MANIFEST_FILE
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def shard_yml
        @shard_yml ||= T.let(
          get_original_file(MANIFEST_FILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def shard_lock
        @shard_lock ||= T.let(
          get_original_file(LOCKFILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("crystal_shards", Dependabot::CrystalShards::FileParser)
