# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/nimble/version"

module Dependabot
  module Nimble
    # A Nimble version range, as written after a package name in `requires`:
    #
    #   1.2.3            the exact version (same as `== 1.2.3`)
    #   >= 1.2  > 1.2  <= 1.2  < 1.2  == 1.2
    #   ^= 1.2.3         `>= 1.2.3` and below the next incompatible version (semver rules)
    #   ~= 1.2.3         `>= 1.2.3` and below the next minor version
    #   >= 1.2 & < 2.0   both (one `&` at most)
    #   *  or nothing    any version
    #
    # `#head` or `#<commit>` name a git ref instead of a version and have no requirement.
    class Requirement < Dependabot::Requirement
      extend T::Sig

      OPERATOR = /\A(?<op>>=|<=|==|\^=|~=|>|<)?\s*(?<version>[0-9A-Za-z][0-9A-Za-z.+\-]*)\z/

      UPPER_OPERATORS = %w(< <=).freeze

      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirement_string: T.nilable(String)).void }
      def initialize(requirement_string = nil)
        super(self.class.gem_constraints(requirement_string))
      end

      # The lower bound a range starts from: the version of its `>=`, `>`, `==`, `^=` or `~=` part.
      sig { params(requirement_string: T.nilable(String)).returns(T.nilable(String)) }
      def self.lower_bound(requirement_string)
        parts(requirement_string).filter_map do |part|
          match = OPERATOR.match(part)
          next unless match
          next if UPPER_OPERATORS.include?(match[:op])

          match[:version]
        end.first
      end

      sig { params(requirement_string: T.nilable(String)).returns(T::Array[String]) }
      def self.parts(requirement_string)
        requirement_string.to_s.split("&").map(&:strip).reject { |part| part.empty? || part == "*" }
      end

      sig { params(requirement_string: T.nilable(String)).returns(T::Array[String]) }
      def self.gem_constraints(requirement_string)
        constraints = parts(requirement_string).flat_map { |part| gem_constraint(part) }
        constraints.empty? ? [">= 0"] : constraints
      end

      sig { params(part: String).returns(T::Array[String]) }
      def self.gem_constraint(part)
        match = OPERATOR.match(part)
        raise Gem::Requirement::BadRequirementError, "Illformed requirement [#{part.inspect}]" unless match

        version = T.must(match[:version])
        case match[:op]
        when nil, "==" then ["= #{version}"]
        when "^=" then [">= #{version}", "< #{next_incompatible(version, semver: true)}"]
        when "~=" then [">= #{version}", "< #{next_incompatible(version, semver: false)}"]
        else ["#{match[:op]} #{version}"]
        end
      end

      # The first version a `^=` or `~=` range excludes; Nimble's getNextIncompatibleVersion.
      sig { params(version: String, semver: T::Boolean).returns(String) }
      def self.next_incompatible(version, semver:)
        numbers = version.split(".")
        original_length = numbers.length
        numbers << "0" while numbers.length < 3
        zeros = numbers.first(2).take_while { |number| number == "0" }.length

        position =
          if semver
            original_length > 1 ? [zeros, 2].min : 0
          else
            [0, original_length - 2].max
          end

        numbers[position] = (numbers.fetch(position).to_i + 1).to_s
        ((position + 1)...numbers.length).each { |index| numbers[index] = "0" }
        numbers.join(".")
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("nimble", Dependabot::Nimble::Requirement)
