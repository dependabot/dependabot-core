# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/codeql/version"

module Dependabot
  module Codeql
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # CodeQL pack dependency ranges use npm-style caret ranges (`^x.y.z`) and
      # the `"*"` wildcard, on top of standard comparison operators.
      CARET_REQUIREMENT = /\A\^\s*(?<version>#{Gem::Version::VERSION_PATTERN})\z/o

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string.to_s)]
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        expanded = requirements.flatten.compact.flat_map { |req| convert_codeql_constraint(req) }
        super(expanded)
      end

      private

      sig { params(requirement: String).returns(T::Array[String]) }
      def convert_codeql_constraint(requirement)
        return [">= 0"] if requirement.strip == "*"

        caret_match = CARET_REQUIREMENT.match(requirement.strip)
        return [requirement] unless caret_match

        expand_caret(T.must(caret_match[:version]))
      end

      # npm-style caret semantics: keep the left-most non-zero segment fixed.
      sig { params(version_string: String).returns(T::Array[String]) }
      def expand_caret(version_string)
        version = Codeql::Version.new(version_string)
        segments = version.segments.map(&:to_i)
        major = segments.fetch(0, 0)
        minor = segments.fetch(1, 0)

        upper =
          if major.positive?
            "#{major + 1}.0.0"
          elsif minor.positive?
            "0.#{minor + 1}.0"
          else
            "0.0.#{segments.fetch(2, 0) + 1}"
          end

        [">= #{version_string}", "< #{upper}"]
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("codeql", Dependabot::Codeql::Requirement)
