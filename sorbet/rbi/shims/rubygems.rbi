# typed: strong
# frozen_string_literal: true

module Gem
  class Version
    # This can be removed one https://github.com/sorbet/sorbet/pull/7314 has been merged
    sig do
      params(
        version: T.any(String, Gem::Version)
      )
        .void
    end
    def initialize(version); end # rubocop:disable Style/RedundantInitialize
  end
end
