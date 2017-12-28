# frozen_string_literal: true

require "dependabot/update_checkers/python/pip"

# Python versions can include a local version identifier, which Ruby can't
# parser. This class augments Gem::Version with local version identifier info.
# See https://www.python.org/dev/peps/pep-0440 for details.

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
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

            return local_version.nil? ? 0 : 1 unless other.is_a?(Pip::Version)

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
        end
      end
    end
  end
end
