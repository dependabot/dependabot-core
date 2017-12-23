# frozen_string_literal: true

require "dependabot/update_checkers/python/pip/version"

# rubocop:disable all
module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        class Requirement < Gem::Requirement
          # Override the version pattern to allow local versions
          quoted  = OPS.keys.map { |k| Regexp.quote k }.join "|"
          PATTERN_RAW =
            "\\s*(#{quoted})?\\s*(#{Pip::Version::VERSION_PATTERN})\\s*"
          PATTERN = /\A#{PATTERN_RAW}\z/

          # Override the parser to create Pip::Versions
          def self.parse obj
            return ["=", obj] if Gem::Version === obj

            unless PATTERN =~ obj.to_s
              raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
            end

            if $1 == ">=" && $2 == "0"
              DefaultRequirement
            else
              [$1 || "=", Pip::Version.new($2)]
            end
          end

          def satisfied_by?(version)
            version = Pip::Version.new(version.to_s)
            super
          end
        end
      end
    end
  end
end
# rubocop:enable all
