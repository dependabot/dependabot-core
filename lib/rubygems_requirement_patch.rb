# frozen_string_literal: true

require "rubygems/requirement"

# See https://github.com/rubygems/rubygems/pull/2554
module Gem
  class Requirement
    # rubocop:disable Style/CaseEquality
    def ==(other)
      return unless Gem::Requirement === other

      # An == check is always necessary
      return false unless requirements == other.requirements

      # An == check is sufficient unless any requirements use ~>
      return true unless _tilde_requirements.any?

      # If any requirements use ~> we check that the strings are equal so that
      # version precision is considered
      _tilde_requirements.map(&:to_s) == other._tilde_requirements.map(&:to_s)
    end
    # rubocop:enable Style/CaseEquality

    protected

    def _tilde_requirements
      requirements.select { |r| r.first == "~>" }
    end
  end
end
