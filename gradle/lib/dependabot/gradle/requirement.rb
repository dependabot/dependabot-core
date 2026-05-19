# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/maven/shared/shared_requirement"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    class Requirement < Dependabot::Maven::Shared::SharedRequirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote k }.join("|")
      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{Gradle::Version::VERSION_PATTERN})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/
      # Like PATTERN, but the leading operator is required
      RUBY_STYLE_PATTERN = /\A\s*(#{quoted})\s*(#{Gradle::Version::VERSION_PATTERN})\s*\z/

      sig { override.returns(Regexp) }
      def self.pattern
        PATTERN
      end

      sig { override.returns(Regexp) }
      def self.ruby_style_pattern
        RUBY_STYLE_PATTERN
      end

      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", Gradle::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Gradle::Version.new(T.must(matches[2]))]
      end

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        split_java_requirement(requirement_string).map do |str|
          new(str)
        end
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Gradle::Version.new(version.to_s)
        super
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("gradle", Dependabot::Gradle::Requirement)
