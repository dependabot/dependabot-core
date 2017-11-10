# frozen_string_literal: true

require "dependabot/update_checkers/python/pip"

module Dependabot
  module UpdateCheckers
    module Python
      class Pip
        class RequirementsUpdater
          attr_reader :requirements, :existing_version,
                      :latest_version, :latest_resolvable_version

          def initialize(requirements:, existing_version:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            if existing_version
              @existing_version = Gem::Version.new(existing_version)
            end

            @latest_version = Gem::Version.new(latest_version) if latest_version

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map { |req| updated_requirement(req) }
          end

          private

          def updated_requirement(req)
            return req unless latest_resolvable_version
            return req unless req.fetch(:requirement)
            return req if new_version_satisfies?(req)
            return req unless req.fetch(:requirement).split(",").count == 1
            return req unless req.fetch(:requirement).start_with?("==")

            updated_requirement_string =
              req[:requirement].sub(PythonRequirementParser::VERSION) do |v|
                at_same_precision(latest_resolvable_version.to_s, v)
              end

            req.merge(requirement: updated_requirement_string)
          end

          def new_version_satisfies?(req)
            equivalent_ruby_requirement(req.fetch(:requirement)).
              satisfied_by?(latest_resolvable_version)
          end

          def equivalent_ruby_requirement(requirement_string)
            requirement_string =
              requirement_string.
              gsub("~=", "~>").
              gsub(/===?/, "=").
              gsub(".*", "")
            Gem::Requirement.new(requirement_string)
          end

          def at_same_precision(new_version, old_version)
            return new_version unless old_version.include?("*")

            count = old_version.split(".").count
            precision = old_version.split(".").index("*")

            new_version.
              split(".").
              first(count).
              map.with_index { |s, i| i < precision ? s : "*" }.
              join(".")
          end
        end
      end
    end
  end
end
