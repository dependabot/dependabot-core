# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_requirement"
require "dependabot/swift/requirement"
require "dependabot/utils"
require "sorbet-runtime"

module Dependabot
  module Swift
    class NativeRequirement
      extend T::Sig

      # TODO: Support pinning to specific revisions
      REGEXP = T.let(
        /(from.*|\.upToNextMajor.*|\.upToNextMinor.*|"[^"]*"\s*\.\.[\.<]\s*"[^"]*".*|exact.*|\.exact.*)/,
        Regexp
      )

      sig { returns(String) }
      attr_reader :declaration

      sig do
        params(
          requirements: T::Array[Dependabot::DependencyRequirement],
          _blk: T.proc.params(declaration: NativeRequirement).returns(String)
        )
          .returns(T::Array[Dependabot::DependencyRequirement])
      end
      def self.map_requirements(requirements, &_blk)
        requirements.map do |requirement|
          next requirement unless requirement.metadata

          requirement_string = requirement.metadata_string(:requirement_string)
          next requirement unless requirement_string

          declaration = new(requirement_string)

          new_declaration = yield(declaration)
          new_requirement = new(new_declaration)

          requirement
            .with_requirement(new_requirement.to_s)
            .with_metadata(requirement_string: new_declaration)
        end
      end

      sig { params(declaration: String).void }
      def initialize(declaration)
        @declaration = declaration

        min, max = parse_declaration(declaration)

        constraint = if min == max
                       ["= #{min}"]
                     elsif closed_range?
                       [">= #{min}", "<= #{max}"]
                     else
                       [">= #{min}", "< #{max}"]
                     end

        @min = T.let(min, String)
        @max = T.let(max, String)
        @requirement = T.let(Requirement.new(constraint), Requirement)
      end

      sig { returns(String) }
      def to_s
        requirement.to_s
      end

      sig { params(version: T.any(String, Gem::Version)).returns(T.nilable(String)) }
      def update_if_needed(version)
        return declaration if requirement.satisfied_by?(version)

        update(version)
      end

      sig { params(version: T.any(String, Gem::Version)).returns(T.nilable(String)) }
      def update(version)
        if single_version_declaration?
          declaration.sub(min, version.to_s)
        elsif closed_range?
          declaration.sub(max, version.to_s)
        elsif range?
          declaration.sub(max, bump_major(version.to_s))
        end
      end

      private

      sig { params(declaration: String).returns([String, String]) }
      def parse_declaration(declaration)
        if up_to_next_major?
          min = quoted_version(declaration)
          max = bump_major(min)
        elsif up_to_next_major_deprecated?
          min = quoted_version(declaration)
          max = bump_major(min)
        elsif up_to_next_minor_deprecated?
          min = quoted_version(declaration)
          max = bump_minor(min)
        elsif closed_range?
          min, max = parse_range("...")
        elsif range?
          min, max = parse_range("..<")
        elsif exact_version?
          min = quoted_version(declaration)
          max = min
        elsif exact_version_deprecated?
          min = quoted_version(declaration)
          max = min
        else
          raise "Unsupported constraint: #{declaration}"
        end

        [T.must(min), T.must(max)]
      end

      sig { params(declaration: String).returns(String) }
      def quoted_version(declaration)
        match = declaration.match(/"([^"]+)"/)
        raise "Missing quoted version: #{declaration}" unless match

        T.must(match[1])
      end

      sig { params(separator: String).returns(T::Array[String]) }
      def parse_range(separator)
        declaration
          .gsub(/("[^"]*"\s*\.\.[\.<]\s*"[^"]*").*/, '\1')
          .split(separator)
          .map { |str| unquote(str.strip) }
      end

      sig { returns(T::Boolean) }
      def single_version_declaration?
        up_to_next_major? || up_to_next_major_deprecated? || up_to_next_minor_deprecated? ||
          exact_version? || exact_version_deprecated?
      end

      sig { params(str: String).returns(String) }
      def bump_major(str)
        transform_version(str) do |s, i|
          i.zero? ? s.to_i + 1 : 0
        end
      end

      sig { params(str: String).returns(String) }
      def bump_minor(str)
        transform_version(str) do |s, i|
          if i.zero?
            s
          else
            (i == 1 ? s.to_i + 1 : 0)
          end
        end
      end

      sig do
        params(str: String, block: T.proc.params(s: String, i: Integer).returns(T.any(String, Integer))).returns(String)
      end
      def transform_version(str, &block)
        str.split(".").map.with_index(&block).join(".")
      end

      sig { returns(T::Boolean) }
      def up_to_next_major?
        declaration.start_with?("from")
      end

      sig { returns(T::Boolean) }
      def up_to_next_major_deprecated?
        declaration.start_with?(".upToNextMajor")
      end

      sig { returns(T::Boolean) }
      def up_to_next_minor_deprecated?
        declaration.start_with?(".upToNextMinor")
      end

      sig { returns(T::Boolean) }
      def exact_version?
        declaration.start_with?("exact")
      end

      sig { returns(T::Boolean) }
      def exact_version_deprecated?
        declaration.start_with?(".exact")
      end

      sig { returns(T::Boolean) }
      def closed_range?
        declaration.include?("...")
      end

      sig { returns(T::Boolean) }
      def range?
        declaration.include?("..<")
      end

      sig { returns(String) }
      attr_reader :min

      sig { returns(String) }
      attr_reader :max

      sig { returns(Requirement) }
      attr_reader :requirement

      sig { params(declaration: String).returns(String) }
      def unquote(declaration)
        T.must(declaration[1..-2])
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("swift", Dependabot::Swift::Requirement)
