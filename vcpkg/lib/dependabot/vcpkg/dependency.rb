# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/git_commit_checker"

require "dependabot/vcpkg"

module Dependabot
  module Vcpkg
    class Dependency < Dependabot::Dependency
      extend T::Sig

      sig { override.returns(T.nilable(String)) }
      def humanized_previous_version
        git_sha?(previous_version) ? humanized_git_version(previous_version) : super
      end

      sig { override.returns(T.nilable(String)) }
      def humanized_version
        git_sha?(version) ? humanized_git_version(version) : super
      end

      private

      sig { params(value: T.nilable(String)).returns(T::Boolean) }
      def git_sha?(value)
        !value.nil? && value.match?(/^[0-9a-f]{40}/)
      end

      sig { params(sha: T.nilable(String)).returns(T.nilable(String)) }
      def humanized_git_version(sha)
        return nil unless sha
        return "`#{sha[0..6]}`" unless git_source?

        tag_name = tag_name_for_sha(sha)
        tag_name || "`#{sha[0..6]}`"
      end

      sig { returns(T::Boolean) }
      def git_source?
        requirements.any? { _1.dig(:source, :type) == "git" }
      end

      sig { params(sha: String).returns(T.nilable(String)) }
      def tag_name_for_sha(sha)
        @tag_name_cache = T.let(@tag_name_cache, T.nilable(T::Hash[String, T.nilable(String)]))
        (@tag_name_cache ||= {}).fetch(sha) do |key|
          @tag_name_cache[key] = fetch_tag_name_for_sha(key)
        end
      end

      sig { params(sha: String).returns(T.nilable(String)) }
      def fetch_tag_name_for_sha(sha)
        git_commit_checker = GitCommitChecker.new(
          dependency: self,
          credentials: []
        )

        # Get all tags and find one that points to this commit
        tags = git_commit_checker.local_tags_for_allowed_versions
        tags.find { |tag_info| sha_matches_tag?(sha, tag_info) }&.dig(:tag)
      rescue Dependabot::GitDependenciesNotReachable
        nil
      end

      sig { params(sha: String, tag_info: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def sha_matches_tag?(sha, tag_info)
        tag_info[:commit_sha] == sha || tag_info[:tag_sha] == sha
      end
    end
  end
end
