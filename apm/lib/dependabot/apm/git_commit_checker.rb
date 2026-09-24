# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/git_commit_checker"
require "dependabot/apm/version"

module Dependabot
  module Apm
    # A GitCommitChecker specialised for APM's strict SemVer 2.0.0 tags.
    #
    # The shared Dependabot::GitCommitChecker recognises and parses version tags
    # with a RubyGems-oriented VERSION_REGEX that is incompatible with APM's
    # strict SemVer grammar in two ways:
    #
    #   * it rejects valid SemVer build metadata (e.g. `v1.2.0+build.5`), so
    #     those releases would never be offered as updates; and
    #   * it accepts non-SemVer tags such as `v1.2.3.4`, which then raise
    #     ArgumentError when the checker builds a strict Apm::Version.
    #
    # Overriding just the version-grammar seams (tag recognition, version
    # extraction and prefix comparison) routes every tag through Apm::Version,
    # while reusing all of the shared cooldown, ignore, prerelease and security
    # handling.
    class GitCommitChecker < Dependabot::GitCommitChecker
      extend T::Sig

      private

      # Recognise a tag as a version only when it is a valid APM SemVer ref, so
      # non-SemVer tags (e.g. `v1.2.3.4`) are dropped before they can raise an
      # ArgumentError, and build-metadata tags (e.g. `v1.2.0+build.5`) are kept.
      sig { override.params(tag: String).returns(T::Boolean) }
      def version_tag?(tag)
        Dependabot::Apm::Version.correct?(tag)
      end

      # Extract the SemVer core of a `v?<semver>` tag, keeping any build metadata
      # so Apm::Version can parse it. Tags reach here only after #version_tag?,
      # so the leading `v` is the only prefix that can be present.
      sig { override.params(name: String).returns(String) }
      def scan_version(name)
        Dependabot::Apm::Version.remove_leading_v(name).to_s
      end

      # APM tags are `v?<semver>`, so the prefix is only the optional `v`. Strip
      # the SemVer core (which the shared VERSION_REGEX cannot remove once build
      # metadata is present) and compare what remains, treating `v` and no prefix
      # as equivalent to match the shared checker's lenient behaviour.
      sig { override.params(tag: String, other_tag: String).returns(T::Boolean) }
      def same_prefix?(tag, other_tag)
        normalize_v_prefix(version_prefix(tag)) == normalize_v_prefix(version_prefix(other_tag))
      end

      sig { params(tag: String).returns(String) }
      def version_prefix(tag)
        tag.delete_suffix(scan_version(tag))
      end
    end
  end
end
