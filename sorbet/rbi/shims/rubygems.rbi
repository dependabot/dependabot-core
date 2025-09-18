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
  end
end
