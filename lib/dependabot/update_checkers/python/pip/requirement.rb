# frozen_string_literal: true

require "dependabot/update_checkers/python/pip/version"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        class Requirement < Gem::Requirement
          quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
          version_pattern = Pip::Version::VERSION_PATTERN

          PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{version_pattern})\\s*"
          PATTERN = /\A#{PATTERN_RAW}\z/

          def self.parse(obj)
            return ["=", Pip::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

            unless (matches = PATTERN.match(obj.to_s))
              msg = "Illformed requirement [#{obj.inspect}]"
              raise BadRequirementError, msg
            end

            return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"
            [matches[1] || "=", Pip::Version.new(matches[2])]
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
