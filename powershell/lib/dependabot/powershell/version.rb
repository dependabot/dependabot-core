# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

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

      sig { override.returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("powershell", Dependabot::Powershell::Version)
