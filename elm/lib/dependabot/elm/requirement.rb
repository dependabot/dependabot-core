# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/elm/version"

module Dependabot
  module Elm
    class Requirement < Dependabot::Requirement
      extend T::Sig

      ELM_PATTERN_RAW =
        T.let(
          "(#{Elm::Version::VERSION_PATTERN}) (<=?) v (<=?) (#{Elm::Version::VERSION_PATTERN})".freeze,
          String
        )
      ELM_PATTERN = /\A#{ELM_PATTERN_RAW}\z/
      ELM_EXACT_PATTERN = /\A#{Elm::Version::VERSION_PATTERN}\z/

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirements: T.any(T.nilable(String), T::Array[T.nilable(String)])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          raise BadRequirementError, "Nil requirement not supported in Elm" if req_string.nil?

          req_string.split(",").map(&:strip).map do |r|
            convert_elm_constraint_to_ruby_constraint(r)
          end
        end

        super(requirements)
      end

      sig { override.params(version: T.any(String, Gem::Version)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Elm::Version.new(version.to_s)
        super
      end

      private

      # Override the parser to create Elm::Versions and return an
      # array of parsed requirements
      sig { params(obj: String).returns(T.any(String, T::Array[String])) }
      def convert_elm_constraint_to_ruby_constraint(obj)
        # If a version is given this is an equals requirement
        return obj if ELM_EXACT_PATTERN.match?(obj.to_s)

        return obj unless (matches = ELM_PATTERN.match(obj.to_s))

        # If the two versions specified are identical this is an equals
        # requirement
        return T.must(matches[4]) if matches[1] == matches[4] && matches[3] == "<="

        [
          [T.must(matches[2]).tr("<", ">"), matches[1]].join(" "),
          [matches[3], matches[4]].join(" ")
        ]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("elm", Dependabot::Elm::Requirement)
