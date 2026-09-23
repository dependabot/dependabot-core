# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  # A git tag (or ref) resolved to a version, as produced by GitCommitChecker's
  # local_tag_for_* / local_ref_for_* methods, e.g.:
  #
  #   {
  #     tag: "v1.2.0",
  #     version: Dependabot::Version.new("1.2.0"),
  #     commit_sha: "a1b2c3...",
  #     tag_sha: "d4e5f6..." # nil for lightweight tags
  #   }
  #
  # Distinct from Dependabot::GitTagWithDetail, which carries a tag name and
  # release date for cooldown handling.
  #
  # Subclasses Hash so it is a drop-in replacement at the many call sites that
  # read entries with [:key] / fetch, while exposing typed readers for the well-known
  # keys. Instances compare equal (Hash#==) to plain hashes with the same
  # content, so existing comparisons and API payloads are unaffected.
  class GitTagDetails < Hash
    extend T::Sig
    extend T::Generic

    K = type_member { { fixed: Symbol } }
    V = type_member { { fixed: Object } }
    Elem = type_member { { fixed: [Symbol, Object] } }

    sig do
      params(
        tag: String,
        version: T.nilable(Gem::Version),
        commit_sha: T.nilable(String),
        tag_sha: T.nilable(String)
      ).void
    end
    def initialize(tag:, version: nil, commit_sha: nil, tag_sha: nil)
      super()
      self[:tag] = tag
      self[:version] = version
      self[:commit_sha] = commit_sha
      self[:tag_sha] = tag_sha
    end

    # The tag or ref name, e.g. "v1.2.0".
    sig { returns(String) }
    def tag
      T.cast(self[:tag], String)
    end

    # The version parsed from the tag name.
    sig { returns(T.nilable(Gem::Version)) }
    def version
      T.cast(self[:version], T.nilable(Gem::Version))
    end

    # The SHA of the commit the tag points at.
    sig { returns(T.nilable(String)) }
    def commit_sha
      T.cast(self[:commit_sha], T.nilable(String))
    end

    # The SHA of the tag object itself (nil for lightweight tags).
    sig { returns(T.nilable(String)) }
    def tag_sha
      T.cast(self[:tag_sha], T.nilable(String))
    end
  end
end
