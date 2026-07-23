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

      sig { override.returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("powershell", Dependabot::Powershell::Version)
