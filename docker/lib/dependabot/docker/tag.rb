# frozen_string_literal: true

require "dependabot/docker/file_parser"

module Dependabot
  module Docker
    class Tag
      VERSION_REGEX = /v?(?<version>[0-9]+(?:\.[0-9]+)*(?:_[0-9]+|\.[a-z0-9]+|-(?:kb)?[0-9]+)*)/i
      VERSION_WITH_SFX = /^#{VERSION_REGEX}(?<suffix>-[a-z][a-z0-9.\-]*)?$/i
      VERSION_WITH_PFX = /^(?<prefix>[a-z][a-z0-9.\-]*-)?#{VERSION_REGEX}$/i
      VERSION_WITH_PFX_AND_SFX = /^(?<prefix>[a-z\-]+-)?#{VERSION_REGEX}(?<suffix>-[a-z\-]+)?$/i
      NAME_WITH_VERSION =
        /
          #{VERSION_WITH_PFX}|
          #{VERSION_WITH_SFX}|
          #{VERSION_WITH_PFX_AND_SFX}
      /x

      attr_reader :name

      def initialize(name)
        @name = name
      end

      def to_s
        name
      end

      def digest?
        name.match?(FileParser::DIGEST)
      end

      def comparable?
        name.match?(NAME_WITH_VERSION)
      end

      def same_precision?(other)
        other.precision == precision
      end

      def same_but_less_precise?(other)
        other.segments.zip(segments).all? do |segment, other_segment|
          segment == other_segment || other_segment.nil?
        end
      end

      def canonical?
        return false unless numeric_version
        return true if name == numeric_version

        # .NET tags are suffixed with -sdk
        return true if name == numeric_version + "-sdk"

        name == "jdk-" + numeric_version
      end

      def prefix
        name.match(NAME_WITH_VERSION).named_captures.fetch("prefix")
      end

      def suffix
        name.match(NAME_WITH_VERSION).named_captures.fetch("suffix")
      end

      def format
        return :year_month if numeric_version.match?(/^[12]\d{3}(?:[.\-]|$)/)
        return :year_month_day if numeric_version.match?(/^[12]\d{5}(?:[.\-]|$)/)
        return :sha_suffixed if name.match?(/(^|\-g?)[0-9a-f]{7,}$/)
        return :build_num if numeric_version.match?(/^\d+$/)

        :normal
      end

      def numeric_version
        return unless comparable?

        name.match(NAME_WITH_VERSION).named_captures.fetch("version").downcase
      end

      def precision
        segments.length
      end

      def segments
        numeric_version.split(/[.-]/)
      end
    end
  end
end
