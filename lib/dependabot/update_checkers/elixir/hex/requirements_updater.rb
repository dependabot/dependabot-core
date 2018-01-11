# frozen_string_literal: true

require "dependabot/update_checkers/elixir/hex/version"
require "dependabot/update_checkers/elixir/hex"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex
        class RequirementsUpdater
          OPERATORS = />=|<=|>|<|==|~>/

          def initialize(requirements:, latest_resolvable_version:)
            @requirements = requirements

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Hex::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map { |req| updated_mixfile_requirement(req) }
          end

          private

          attr_reader :requirements, :latest_resolvable_version

          def updated_mixfile_requirement(req)
            return req unless latest_resolvable_version

            requirements = req[:requirement].split(",")

            new_requirement =
              if requirements.count > 1
                # TODO: This is bad, and I should feel bad
                latest_resolvable_version.to_s
              elsif requirements.first.include?("<")
                update_greatest_version(
                  Gem::Requirement.new(requirements.first),
                  latest_resolvable_version
                ).to_s
              else
                # TODO: This is wrong for > and >= specifiers
                requirement = requirements.first
                op = requirement.match(OPERATORS).to_s
                version = Hex::Version.new(requirement.gsub(OPERATORS, ""))
                updated_version = at_same_precision(
                  latest_resolvable_version,
                  version
                )
                "#{op} #{updated_version}".strip
              end

            req.merge(requirement: new_requirement)
          end

          def at_same_precision(new_version, old_version)
            precision = old_version.to_s.split(".").count
            new_version.to_s.split(".").first(precision).join(".")
          end

          # Updates the version in a "<" or "<=" constraint to allow the given
          # version
          def update_greatest_version(requirement, version_to_be_permitted)
            if version_to_be_permitted.is_a?(String)
              version_to_be_permitted =
                Hex::Version.new(version_to_be_permitted)
            end
            op, version = requirement.requirements.first
            version = version.release if version.prerelease?

            index_to_update =
              version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

            new_segments = version.segments.map.with_index do |_, index|
              if index < index_to_update
                version_to_be_permitted.segments[index]
              elsif index == index_to_update
                version_to_be_permitted.segments[index] + 1
              else 0
              end
            end

            Gem::Requirement.new("#{op} #{new_segments.join('.')}")
          end
        end
      end
    end
  end
end
