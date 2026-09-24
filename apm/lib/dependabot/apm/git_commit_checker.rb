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
    # extraction, prefix comparison and latest-tag selection) routes every tag
    # through Apm::Version, while reusing all of the shared cooldown, ignore,
    # prerelease and security handling.
    #
    # Besides plain `v?<semver>` tags, APM also recognises package-scoped tags
    # so a monorepo can release each package independently: `{name}_v{version}`,
    # `{name}--v{version}` and `{name}-v{version}`, where `{name}` is the
    # package's own name (the repository name, or the final component of a
    # virtual package path). A repository that only publishes `review--v1.5.0`
    # would otherwise offer no update, so those forms are parsed too, with the
    # accepted prefix scoped to this dependency's package name. That grammar
    # lives in `Apm::Version.semver_from_ref`, shared with the file parser and
    # update checker so every consumer reads refs identically.
    class GitCommitChecker < Dependabot::GitCommitChecker
      extend T::Sig

      # Build metadata is not part of SemVer precedence, so tags such as
      # `v1.3.0+build.5` and `v1.3.0+build.9` compare equal and the inherited
      # `max_by { version_from_tag(...) }` would keep whichever the remote
      # advertised first. Break that tie by the highest full tag string, as APM
      # does, so latest-tag selection is deterministic regardless of ref order.
      # Public to match the shared checker, which exposes this selection seam.
      sig { override.params(tags: T::Array[Dependabot::GitRef]).returns(T.nilable(Dependabot::GitTagDetails)) }
      def max_local_tag(tags)
        max_version_tag = tags.max_by { |tag| [version_from_tag(tag), tag.name] }

        to_local_tag(max_version_tag)
      end

      private

      # Recognise a tag as a version only when it is a valid APM SemVer ref
      # (optionally package-scoped), so non-SemVer tags (e.g. `v1.2.3.4`) are
      # dropped before they can raise an ArgumentError, while build-metadata
      # tags (e.g. `v1.2.0+build.5`) and package-scoped tags (e.g.
      # `review--v1.5.0`) are kept.
      sig { override.params(tag: String).returns(T::Boolean) }
      def version_tag?(tag)
        !Dependabot::Apm::Version.semver_from_ref(tag, dependency_name: dependency.name).nil?
      end

      # Extract the SemVer core of a tag, keeping any build metadata so
      # Apm::Version can parse it. Tags reach here only after #version_tag?, so
      # the tag is always a plain `v?<semver>` or a recognised package-scoped
      # form and the extraction never returns nil.
      sig { override.params(name: String).returns(String) }
      def scan_version(name)
        T.must(Dependabot::Apm::Version.semver_from_ref(name, dependency_name: dependency.name))
      end

      # An APM tag's prefix is whatever precedes its SemVer core: the optional
      # `v` on a plain tag, or `{name}_v` / `{name}--v` / `{name}-v` on a
      # package-scoped one. Strip the SemVer core (which the shared VERSION_REGEX
      # cannot remove once build metadata is present) and compare what remains,
      # treating `v` and no prefix as equivalent to match the shared checker's
      # lenient behaviour, so a pinned plain tag keeps resolving plain tags and a
      # pinned scoped tag keeps resolving that package's scoped tags.
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
