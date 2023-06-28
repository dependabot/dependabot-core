# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/swift/requirement"
require "dependabot/swift/version"

module Dependabot
  module Swift
    class NativeRequirement
      attr_reader :declaration

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

        @min = min
        @max = max
        @requirement = Requirement.new(constraint)
      end

      def to_s
        requirement.to_s
      end

      private

      def parse_declaration(declaration)
        if up_to_next_major?
          min = declaration.gsub(/\Afrom\s*:\s*"(\S+)"\s*\z/, '\1')
          max = bump_major(min)
        elsif up_to_next_major_deprecated?
          min = declaration.gsub(/\A\.upToNextMajor\s*\(\s*from\s*:\s*"(\S+)"\s*\)\z/, '\1')
          max = bump_major(min)
        elsif up_to_next_minor_deprecated?
          min = declaration.gsub(/\A\.upToNextMinor\s*\(\s*from\s*:\s*"(\S+)"\s*\)\z/, '\1')
          max = bump_minor(min)
        elsif closed_range?
          min, max = parse_range("...")
        elsif range?
          min, max = parse_range("..<")
        elsif exact_version?
          min = declaration.gsub(/\Aexact\s*:\s*"(\S+)"\s*\z/, '\1')
          max = min
        elsif exact_version_deprecated?
          min = declaration.gsub(/\A\.exact\s*\(\s*"(\S+)"\s*\)\z/, '\1')
          max = min
        else
          raise "Unsupported constraint: #{declaration}"
        end

        [min, max]
      end

      def parse_range(separator)
        declaration.split(separator).map { |str| unquote(str) }
      end

      def single_version_declaration?
        up_to_next_major? || up_to_next_major_deprecated? || up_to_next_minor? ||
          exact_version? || exact_version_deprecated?
      end

      def bump_major(str)
        transform_version(str) do |s, i|
          i.zero? ? s.to_i + 1 : 0
        end
      end

      def bump_minor(str)
        transform_version(str) do |s, i|
          if i.zero?
            s
          else
            (i == 1 ? s.to_i + 1 : 0)
          end
        end
      end

      def transform_version(str, &block)
        str.split(".").map.with_index(&block).join(".")
      end

      def up_to_next_major?
        declaration.start_with?("from")
      end

      def up_to_next_major_deprecated?
        declaration.start_with?(".upToNextMajor")
      end

      def up_to_next_minor_deprecated?
        declaration.start_with?(".upToNextMinor")
      end

      def exact_version?
        declaration.start_with?("exact")
      end

      def exact_version_deprecated?
        declaration.start_with?(".exact")
      end

      def closed_range?
        declaration.include?("...")
      end

      def range?
        declaration.include?("..<")
      end

      attr_reader :min, :max, :requirement

      def unquote(declaration)
        declaration[1..-2]
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("swift", Dependabot::Swift::Requirement)
