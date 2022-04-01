# frozen_string_literal: true

require "dependabot/utils"
require "rubygems_version_patch"

# Python versions can include a local version identifier, which Ruby can't
# parse. This class augments Gem::Version with local version identifier info.
# See https://www.python.org/dev/peps/pep-0440 for details.

module Dependabot
  module Python
    class Version < Gem::Version
      attr_reader :epoch
      attr_reader :local_version
      attr_reader :post_release_version

      # See https://peps.python.org/pep-0440/#appendix-b-parsing-version-strings-with-regular-expressions
      VERSION_PATTERN = 'v?([1-9][0-9]*!)?[0-9]+[0-9a-zA-Z]*(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                        '(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/.freeze

      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      def initialize(version)
        @version_string = version.to_s
        version, @local_version = version.split("+")
        version ||= ""
        version = version.gsub(/^v/, "")
        if version.include?("!")
          @epoch, version = version.split("!")
        else
          @epoch = "0"
        end
        version = normalise_prerelease(version)
        version, @post_release_version = version.split(/\.r(?=\d)/)
        version ||= ""
        @local_version = normalise_prerelease(@local_version) if @local_version
        super
      end

      def to_s
        @version_string
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      def <=>(other)
        other = Version.new(other.to_s) unless other.is_a?(Python::Version)

        epoch_comparison = epoch_comparison(other)
        return epoch_comparison unless epoch_comparison.zero?

        version_comparison = super(other)
        return version_comparison unless version_comparison.zero?

        post_version_comparison = post_version_comparison(other)
        return post_version_comparison unless post_version_comparison.zero?

        local_version_comparison(other)
      end

      private

      def epoch_comparison(other)
        epoch.to_i <=> other.epoch.to_i
      end

      def post_version_comparison(other)
        unless other.post_release_version
          return post_release_version.nil? ? 0 : 1
        end

        return -1 if post_release_version.nil?

        post_release_version.to_i <=> other.post_release_version.to_i
      end

      def local_version_comparison(other)
        # Local version comparison works differently in Python: `1.0.beta`
        # compares as greater than `1.0`. To accommodate, we make the
        # strings the same length before comparing.
        lhsegments = local_version.to_s.split(".").map(&:downcase)
        rhsegments = other.local_version.to_s.split(".").map(&:downcase)
        limit = [lhsegments.count, rhsegments.count].min

        lhs = ["1", *lhsegments.first(limit)].join(".")
        rhs = ["1", *rhsegments.first(limit)].join(".")

        local_comparison = Gem::Version.new(lhs) <=> Gem::Version.new(rhs)

        return local_comparison unless local_comparison.zero?

        lhsegments.count <=> rhsegments.count
      end

      def normalise_prerelease(version)
        # Python has reserved words for release states, which are treated
        # as equal (e.g., preview, pre and rc).
        # Further, Python treats dashes as a separator between version
        # parts and treats the alphabetical characters in strings as the
        # start of a new version part (so 1.1a2 == 1.1.alpha.2).
        version.
          gsub("alpha", "a").
          gsub("beta", "b").
          gsub("preview", "c").
          gsub("pre", "c").
          gsub("post", "r").
          gsub("rev", "r").
          gsub(/([\d.\-_])rc([\d.\-_])?/, '\1c\2').
          tr("-", ".").
          gsub(/(\d)([a-z])/i, '\1.\2')
      end
    end
  end
end

Dependabot::Utils.
  register_version_class("pip", Dependabot::Python::Version)
