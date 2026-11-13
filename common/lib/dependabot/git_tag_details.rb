# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  # A tag or ref resolved by GitCommitChecker.
  class GitTagDetails < T::ImmutableStruct
    extend T::Sig

    const :tag, String
    const :version, T.nilable(Gem::Version), default: nil
    const :commit_sha, T.nilable(String), default: nil
    const :tag_sha, T.nilable(String), default: nil

    sig { params(other: BasicObject).returns(T::Boolean) }
    def ==(other)
      case other
      when GitTagDetails
        to_h == other.to_h
      else
        false
      end
    end

    sig { returns(T::Hash[Symbol, Object]) }
    def to_h
      {
        tag: tag,
        version: version,
        commit_sha: commit_sha,
        tag_sha: tag_sha
      }
    end
  end
end
