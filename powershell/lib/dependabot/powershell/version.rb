# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"
require "dependabot/powershell/module_specification_version"

module Dependabot
  module Powershell
    # PowerShell module versions follow standard semantic versioning
    # (Major.Minor.Build.Revision), so no custom comparison logic is needed
    # beyond what Dependabot::Version already provides. We do override
    # `#to_s`/`#inspect` because `Gem::Version#to_s` normalizes prerelease
    # segments (e.g. "5.5.0-beta1" becomes "5.5.0.pre.beta1"), which would
    # otherwise leak into rewritten requirement strings.
    class Version < Dependabot::Version
      extend T::Sig

      NumericComponents = T.type_alias { [Integer, Integer, Integer, Integer] }
      VERSION_CORE_PATTERN = /\A([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?(?:\.([0-9]+))?/

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)

        super
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      # PowerShell's own module-loading rules treat RequiredVersion as an
      # exact string match rather than Gem::Version's numeric equality
      # (which pads missing segments with zero, e.g. treating "0.12" and
      # "0.12.0" as equal). Comparing the original version strings instead
      # keeps `Requirement#satisfied_by?` from reporting an installed
      # "0.12.0" as satisfying a declared `RequiredVersion = '0.12'` (or
      # vice versa) when PowerShell itself would not consider them equal.
      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Gem::Version)

        to_s == other.to_s
      end

      sig { params(other: Object).returns(T::Boolean) }
      def eql?(other)
        self == other
      end

      sig { override.returns(Integer) }
      def hash
        to_s.hash
      end

      sig { override.returns(T::Array[String]) }
      def ignored_patch_versions
        native_version = ModuleSpecificationVersion.normalize(to_s)
        return super unless native_version

        components = native_version.split(".")
        padded_versions = []
        while components.length < ModuleSpecificationVersion::MAX_COMPONENT_COUNT
          components << "0"
          padded_versions << "= #{components.join('.')}"
        end

        super + padded_versions
      end

      # Same-core prerelease-only changes are intentionally unclassified.
      sig do
        override
          .params(from_version: String, to_version: String)
          .returns(T.nilable(String))
      end
      def self.update_type(from_version, to_version)
        from_components = numeric_components(from_version)
        to_components = numeric_components(to_version)
        return unless from_components && to_components

        from_major, from_minor, from_patch, from_revision = from_components
        to_major, to_minor, to_patch, to_revision = to_components

        return "major" if to_major > from_major
        return "minor" if to_major == from_major && to_minor > from_minor
        return "patch" if [to_major, to_minor] == [from_major, from_minor] && to_patch > from_patch

        "patch" if [to_major, to_minor, to_patch] == [from_major, from_minor, from_patch] &&
                   to_revision > from_revision
      end

      sig { override.returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { params(version: String).returns(T.nilable(NumericComponents)) }
      def self.numeric_components(version)
        return unless correct?(version)

        match = VERSION_CORE_PATTERN.match(version)
        return unless match

        [
          T.must(match[1]).to_i,
          (match[2] || "-1").to_i,
          (match[3] || "-1").to_i,
          (match[4] || "-1").to_i
        ]
      end
      private_class_method :numeric_components
    end
  end
end

Dependabot::Utils
  .register_version_class("powershell", Dependabot::Powershell::Version)
