# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/maven/version"
require "dependabot/maven/shared/shared_requirement"

module Dependabot
  module Maven
    class Requirement < Dependabot::Maven::Shared::SharedRequirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote k }.join("|")
      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{Maven::Version::VERSION_PATTERN})\\s*".freeze, String)
      PATTERN = T.let(/\A#{PATTERN_RAW}\z/, Regexp)
      # Like PATTERN, but the leading operator is required
      RUBY_STYLE_PATTERN = T.let(/\A\s*(#{quoted})\s*(#{Maven::Version::VERSION_PATTERN})\s*\z/, Regexp)

      sig { override.returns(Regexp) }
      def self.pattern
        PATTERN
      end

      sig { override.returns(Regexp) }
      def self.ruby_style_pattern
        RUBY_STYLE_PATTERN
      end

      sig { params(obj: T.any(String, Gem::Version)).returns(T::Array[T.any(String, T.untyped)]) }
      def self.parse(obj)
        return ["=", Maven::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Maven::Version.new(T.must(matches[2]))]
      end

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        split_java_requirement(requirement_string).map do |str|
          new(str)
        end
      end

      sig { params(version: T.untyped).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Maven::Version.new(version.to_s)
        super
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("maven", Dependabot::Maven::Requirement)
