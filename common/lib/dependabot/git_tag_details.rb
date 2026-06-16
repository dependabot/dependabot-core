# typed: strict
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
  # read entries with [:key] / fetch and treat them as
  # T::Hash[Symbol, T.untyped], while exposing typed readers for the well-known
  # keys. Instances compare equal (Hash#==) to plain hashes with the same
  # content, so existing comparisons and API payloads are unaffected.
  class GitTagDetails < Hash
    extend T::Sig
    extend T::Generic

    # The values are heterogeneous (strings and a version object), so this
    # bridge class is necessarily untyped at the Hash level; the typed readers
    # below are the migration path.
    # rubocop:disable Sorbet/ForbidTUntyped
    K = type_member { { fixed: Symbol } }
    V = type_member { { fixed: T.untyped } }
    Elem = type_member { { fixed: [Symbol, T.untyped] } }
    # rubocop:enable Sorbet/ForbidTUntyped

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
      self[:tag]
    end

    # The version parsed from the tag name.
    sig { returns(T.nilable(Gem::Version)) }
    def version
      self[:version]
    end

    # The SHA of the commit the tag points at.
    sig { returns(T.nilable(String)) }
    def commit_sha
      self[:commit_sha]
    end

    # The SHA of the tag object itself (nil for lightweight tags).
    sig { returns(T.nilable(String)) }
    def tag_sha
      self[:tag_sha]
    end
  end
end
