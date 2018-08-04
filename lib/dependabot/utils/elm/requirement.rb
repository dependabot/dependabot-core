# frozen_string_literal: true

require "dependabot/utils/elm/version"

module Dependabot
  module Utils
    module Elm
      class Requirement < Gem::Requirement
        # Override the version pattern to allow local versions
        PATTERN_RAW =
          "(#{Utils::Elm::Version::VERSION_PATTERN}) (<=?) v (<=?) " \
          "(#{Utils::Elm::Version::VERSION_PATTERN})"
        PATTERN = /\A#{PATTERN_RAW}\z/

        # Returns an array of requirements. At least one requirement from the
        # returned array must be satisfied for a version to be valid.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
        end

        # Override the parser to create Utils::Elm::Versions and return an
        # array of parsed requirements
        def self.parse(obj)
          unless (matches = PATTERN.match(obj.to_s))
            msg = "Illformed requirement #{obj.inspect}"
            raise BadRequirementError, msg
          end

          # If the two versions specified are identical this is a equals
          # requirement
          if matches[1] == matches[4] && matches[3] == "<="
            return [["=", Utils::Elm::Version.new(matches[4])]]
          end

          [
            [matches[2].tr("<", ">"), Utils::Elm::Version.new(matches[1])],
            [matches[3], Utils::Elm::Version.new(matches[4])]
          ]
        end

        # Overwrite superclass method to use `flat_map`
        def initialize(*requirements)
          if requirements.any?(&:nil?)
            raise BadRequirementError, "Nil requirement not supported in Elm"
          end

          requirements = requirements.flatten
          requirements.compact!
          requirements.uniq!

          if requirements.empty?
            @requirements = [DefaultRequirement]
          else
            @requirements = requirements.flat_map { |r| self.class.parse(r) }
            sort_requirements!
          end
        end

        # Overwrite superclass method to use `flat_map`
        def concat(new)
          new = new.flatten
          new.compact!
          new.uniq!
          new = new.flat_map { |r| self.class.parse(r) }

          @requirements.concat new
          sort_requirements!
        end

        def sort_requirements!
          @requirements.sort! do |l, r|
            comp = l.last <=> r.last # first, sort by the requirement's version
            next comp unless comp.zero?
            l.first <=> r.first # then, sort by the operator (for stability)
          end
        end

        def satisfied_by?(version)
          version = Utils::Elm::Version.new(version.to_s)
          super
        end
      end
    end
  end
end
