# frozen_string_literal: true
require "gems"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Gemspec < Dependabot::UpdateCheckers::Base
        class UnfixableRequirement < StandardError; end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          latest_version
        end

        def updated_requirement
          requirements =
            original_requirement.as_list.map { |r| Gem::Requirement.new(r) }

          updated_requirements =
            requirements.flat_map do |r|
              r.satisfied_by?(latest_version) ? r : fixed_requirements(r)
            end

          updated_requirements.sort_by! { |r| r.requirements.first.last }
          updated_requirements.map(&:to_s).join(", ")
        rescue UnfixableRequirement
          nil
        end

        def needs_update?
          !original_requirement.satisfied_by?(latest_version) &&
            !updated_requirement.nil?
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

        def original_requirement
          Gem::Requirement.new(*dependency.version.split(","))
        end

        def fixed_requirements(r)
          op, version = r.requirements.first

          if version.segments.any? { |s| !s.instance_of?(Integer) }
            # Ignore constraints with non-integer values for now.
            # TODO: Handle pre-release constraints properly.
            raise UnfixableRequirement
          end

          case op
          when "=", nil then [Gem::Requirement.new("#{op} #{latest_version}")]
          when "<", "<=" then [updated_greatest_version(r)]
          when "~>" then updated_twidle_requirements(r)
          when "!=", ">", ">=" then raise UnfixableRequirement
          else raise "Unexpected operation for requirement: #{op}"
          end
        end

        def updated_twidle_requirements(requirement)
          version = requirement.requirements.first.last

          index_to_update = version.segments.count - 2

          ub_segments = latest_version.segments
          ub_segments << 0 while ub_segments.count <= index_to_update
          ub_segments = ub_segments[0..index_to_update]
          ub_segments[index_to_update] += 1

          lb_segments = version.segments
          lb_segments.pop while lb_segments.last.zero?

          # Ensure versions have the same length as each other (cosmetic)
          length = [lb_segments.count, ub_segments.count].max
          lb_segments.fill(0, lb_segments.count...length)
          ub_segments.fill(0, ub_segments.count...length)

          [
            Gem::Requirement.new(">= #{lb_segments.join('.')}"),
            Gem::Requirement.new("< #{ub_segments.join('.')}")
          ]
        end

        # Updates the version in a "<" or "<=" constraint to allow the latest
        # version
        def updated_greatest_version(requirement)
          op, version = requirement.requirements.first

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

          Gem::Requirement.new("#{op} #{new_segments.join('.')}")
        end
      end
    end
  end
end
