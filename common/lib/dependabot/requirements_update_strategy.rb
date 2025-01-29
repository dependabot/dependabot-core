# typed: strong
# frozen_string_literal: true

module Dependabot
  class RequirementsUpdateStrategy < T::Enum
    enums do
      BumpVersions = new("bump_versions")
      BumpVersionsIfNecessary = new("bump_versions_if_necessary")
      LockfileOnly = new("lockfile_only")
      WidenRanges = new("widen_ranges")
    end

    extend T::Sig

    sig { returns(T::Boolean) }
    def lockfile_only?
      self == LockfileOnly
    end
  end
end
