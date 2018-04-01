# frozen_string_literal: true

# Python versions can include a local version identifier, which Ruby can't
# parser. This class augments Gem::Version with local version identifier info.
# See https://www.python.org/dev/peps/pep-0440 for details.

module Dependabot
  module Utils
    module Python
      class Version < Gem::Version
        attr_reader :local_version

        VERSION_PATTERN = Gem::Version::VERSION_PATTERN +
                          '(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?'

        def self.correct?(version)
          super(version.to_s.split("+").first)
        end

        def initialize(version)
          @version_string = version.to_s
          version, @local_version = version.split("+")
          version = normalise_prerelease(version)
          if @local_version
            @local_version = normalise_prerelease(@local_version)
          end
          super
        end

        def to_s
          @version_string
        end

        def inspect # :nodoc:
          "#<#{self.class} #{@version_string}>"
        end

        def <=>(other)
          version_comparison = super(other)
          return version_comparison unless version_comparison.zero?

          unless other.is_a?(Utils::Python::Version)
            return local_version.nil? ? 0 : 1
          end

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

        private

        def normalise_prerelease(version)
          # Python has reserved words for release states, which are treated
          # as equal (e.g., preview, pre and rc).
          # Further, Python treats dashes as a separator between version
          # parts and treats the alphabetical characters in strings as the
          # start of a new version part (so 1.1a2 == 1.1.alpha.2).
          version.
            gsub("alpha", "a").
            gsub("beta", "b").
            gsub("preview", "rc").
            gsub("pre", "rc").
            gsub(/([\d.\-_])c([\d.\-_])?/, '\1rc\2').
            tr("-", ".").
            gsub(/(\d)([a-z])/i, '\1.\2')
        end
      end
    end
  end
end
