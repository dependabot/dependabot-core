# typed: strong
# frozen_string_literal: true

require "sawyer"
require "sorbet-runtime"

module Dependabot
  class GitCommitChecker
    # Typed view over the release fields returned by Octokit.
    class GitHubRelease < T::ImmutableStruct
      extend T::Sig

      const :tag_name, String
      const :prerelease, T::Boolean

      sig { params(resource: Sawyer::Resource).returns(T.nilable(GitHubRelease)) }
      def self.from_resource(resource)
        tag_name = T.cast(resource[:tag_name], Object)
        return unless tag_name.is_a?(String)

        prerelease = T.cast(resource[:prerelease], Object)
        new(tag_name: tag_name, prerelease: prerelease == true)
      end
    end
  end
end
