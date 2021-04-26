# frozen_string_literal: true

module Dependabot
  # Allows us to check requirements for non-numeric versions, so that we can
  # ignore git dependencies.
  class Requirement < Gem::Requirement
    GIT_SHA_IGNORE_PREFIX = "!!"
    GIT_SHA_IGNORE_REGEX = /\A#{GIT_SHA_IGNORE_PREFIX}/.freeze

    def self.parse(obj)
      if obj.is_a?(String) && obj.strip.match?(GIT_SHA_IGNORE_REGEX)
        return [GIT_SHA_IGNORE_PREFIX, obj.gsub(GIT_SHA_IGNORE_REGEX, "").strip]
      end

      super
    end

    def satisfied_by?(version)
      if requirements.any? { |op, _| op == GIT_SHA_IGNORE_PREFIX }
        rv = requirements.find { |op, _| op == GIT_SHA_IGNORE_PREFIX }.last
        return !version.nil? && rv != version
      end

      super
    end
  end
end

