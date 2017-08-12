# frozen_string_literal: true
require "gems"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Gemspec < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          latest_version
        end

        def needs_update?
          !dependency.requirement.satisfied_by?(latest_version) &&
            !updated_requirement.nil?
        end

        def updated_dependency
          Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirement: updated_requirement,
            previous_version: dependency.version,
            package_manager: dependency.package_manager
          )
        end

        private

        def fetch_latest_version
          # Note: Rubygems excludes pre-releases from the `Gems.info` response.
          # We might want to add them back in?
          latest_info = Gems.info(dependency.name)

          if latest_info["version"].nil?
            raise "No version in Rubygems info:\n\n #{latest_info}"
          end

          Gem::Version.new(latest_info["version"])
        rescue JSON::ParserError
          # Replace with Gems::NotFound error if/when
          # https://github.com/rubygems/gems/pull/38 is merged.
          raise "Dependency not found on Rubygems: #{dependency.name}"
        end

        def updated_requirement
          requirements =
            dependency.requirement.as_list.map { |r| Gem::Requirement.new(r) }

          updated_requirements =
            requirements.map do |r|
              next r if r.satisfied_by?(latest_version)
              fixed_requirement(r)
            end

          updated_requirement = updated_requirements.shift
          updated_requirement.concat(updated_requirements)
          updated_requirement
        rescue ArgumentError
          # TODO! Use something other than ArgumentError here
          nil
        end

        def fixed_requirement(r)
          op, version = r.requirements.first

          case op
          when "=", nil
            Gem::Requirement.new("#{op} #{latest_version}")
          when "<", "<="
            Gem::Requirement.new("#{op} #{updated_constraint_version(version)}")
          when "~>"
            Gem::Requirement.new(
              ">= #{version}",
              "< #{updated_constraint_version(version)}"
            )
          when "!=", ">", ">="
            raise ArgumentError
          end
        end

        def updated_constraint_version(version)
          # Ignore constraints with non-integer values for now.
          # TODO: Handle pre-release constraints properly.
          if version.segments.any? { |s| !s.instance_of?(Integer) }
            raise ArgumentError
          end

          index_to_update =
            version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

          new_segments = version.segments.map.with_index do |_, index|
            if index < index_to_update
              latest_version.segments[index]
            elsif index == index_to_update
              latest_version.segments[index] + 1
            else
              0
            end
          end

          Gem::Version.new(new_segments.join("."))
        end
      end
    end
  end
end
