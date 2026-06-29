# typed: strong
# frozen_string_literal: true

module Gem
  class Version
    # Extended version parameter type to support nilable values for Dependabot::Version
    VersionParameter = T.type_alias { T.nilable(T.any(String, Integer, Gem::Version)) }

    sig { params(version: VersionParameter).returns(Gem::Version) }
    def self.new(version); end

    sig { params(version: VersionParameter).void }
    def initialize(version); end

    # RubyGems 4 internals used by Dependabot::Version to keep the eager sort-key
    # computation from raising on versions with alphabetic segments.
    sig { returns(T::Array[T.any(String, Integer)]) }
    def canonical_segments; end

    sig { returns(T.nilable(Integer)) }
    def compute_sort_key; end
  end
end
