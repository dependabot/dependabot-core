# typed: true
# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/swift/requirement"

module Dependabot
  module Swift
    class NativeRequirement
      # TODO: Support pinning to specific revisions
      REGEXP = /(from.*|\.upToNextMajor.*|\.upToNextMinor.*|".*"\s*\.\.[\.<]\s*".*"|exact.*|\.exact.*)/

      attr_reader :declaration

      def self.map_requirements(requirements)
        requirements.map do |requirement|
          declaration = new(requirement[:metadata][:requirement_string])

          new_declaration = yield(declaration)
          new_requirement = new(new_declaration)

          requirement.merge(
            requirement: new_requirement.to_s,
            metadata: { requirement_string: new_declaration }
          )
        end
      end

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

      def update_if_needed(version)
        return declaration if requirement.satisfied_by?(version)

        update(version)
      end

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
        declaration.split(separator).map { |str| unquote(str.strip) }
      end

      def single_version_declaration?
        up_to_next_major? || up_to_next_major_deprecated? || up_to_next_minor_deprecated? ||
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

      attr_reader :min
      attr_reader :max
      attr_reader :requirement

      def unquote(declaration)
        declaration[1..-2]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("swift", Dependabot::Swift::Requirement)
