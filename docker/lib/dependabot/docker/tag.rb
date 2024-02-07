# typed: true
# frozen_string_literal: true

require "dependabot/docker/file_parser"

module Dependabot
  module Docker
    class Tag
      WORDS_WITH_BUILD = /(?:(?:-[a-z]+)+-[0-9]+)+/
      VERSION_REGEX = /v?(?<version>[0-9]+(?:\.[0-9]+)*(?:_[0-9]+|\.[a-z0-9]+|#{WORDS_WITH_BUILD}|-(?:kb)?[0-9]+)*)/i
      VERSION_WITH_SFX = /^#{VERSION_REGEX}(?<suffix>-[a-z][a-z0-9.\-]*)?$/i
      VERSION_WITH_PFX = /^(?<prefix>[a-z][a-z0-9.\-_]*-)?#{VERSION_REGEX}$/i
      VERSION_WITH_PFX_AND_SFX = /^(?<prefix>[a-z\-_]+-)?#{VERSION_REGEX}(?<suffix>-[a-z\-]+)?$/i
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

      def looks_like_prerelease?
        numeric_version.match?(/[a-zA-Z]/)
      end

      def comparable_to?(other)
        return false unless comparable?

        other_prefix = other.prefix
        other_suffix = other.suffix
        other_format = other.format

        equal_prefix = prefix == other_prefix
        equal_format = format == other_format
        return equal_prefix && equal_format if other_format == :sha_suffixed

        equal_suffix = suffix == other_suffix
        equal_prefix && equal_format && equal_suffix
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

      def version
        name.match(NAME_WITH_VERSION).named_captures.fetch("version")
      end

      def format
        return :sha_suffixed if name.match?(/(^|\-g?)[0-9a-f]{7,}$/)
        return :year_month if version.match?(/^[12]\d{3}(?:[.\-]|$)/)
        return :year_month_day if version.match?(/^[12](?:\d{5}|\d{7})(?:[.\-]|$)/)
        return :build_num if version.match?(/^\d+$/)

        # As an example, "21-ea-32", "22-ea-7", and "22-ea-jdk-nanoserver-1809"
        # are mapped to "<version>-ea-<build_num>", "<version>-ea-<build_num>",
        # and "<version>-ea-jdk-nanoserver-<build_num>" respectively.
        #
        # That means only "22-ea-7" will be considered as a viable update
        # candidate for "21-ea-32", since it's the only one that respects that
        # format.
        if version.match?(WORDS_WITH_BUILD)
          return :"<version>#{version.match(WORDS_WITH_BUILD).to_s.gsub(/-[0-9]+/, '-<build_num>')}"
        end

        :normal
      end

      def numeric_version
        return unless comparable?

        version.gsub(/kb/i, "").gsub(/-[a-z]+/, "").downcase
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
