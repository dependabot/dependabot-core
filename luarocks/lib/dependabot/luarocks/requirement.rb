# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/luarocks/version"

module Dependabot
  module Luarocks
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        return [new(">= 0")] if requirement_string.nil? || requirement_string.strip.empty?

        requirement_string.split(",").map { |req| new(req.strip) }
      end

      sig { params(requirements: T.any(T.nilable(String), T::Array[T.nilable(String)])).void }
      def initialize(*requirements)
        normalized = requirements.flatten.compact.map { |req| normalize_requirement(req) }
        super(normalized)
      end

      sig { override.params(version: T.any(String, Gem::Version)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Luarocks::Version.new(version.to_s)
        super
      end

      private

      sig { params(requirement: String).returns(String) }
      def normalize_requirement(requirement)
        trimmed = requirement.strip
        return trimmed if trimmed.empty?

        if trimmed.start_with?("==")
          "= #{trimmed.delete_prefix('==').strip}"
        elsif trimmed.match?(/\A[<>=~]/)
          trimmed
        else
          "= #{trimmed}"
        end
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("luarocks", Dependabot::Luarocks::Requirement)
