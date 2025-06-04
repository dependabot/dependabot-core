# typed: strong
# frozen_string_literal: true

module Gem
  class Version
    sig do
      params(
        version: T.nilable(
          T.any(
            String,
            Integer,
            Gem::Version
          )
        )
      )
        .returns(Gem::Version)
    end
    def self.new(version); end

    sig do
      params(
        version: T.nilable(
          T.any(
            String,
            Integer,
            Gem::Version
          )
        )
      )
        .void
    end
    def initialize(version); end
  end
end
