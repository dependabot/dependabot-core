# frozen_string_literal: true

require "dependabot/update_checkers/go/dep"
require "dependabot/utils/go/requirement"
require "dependabot/utils/go/version"

module Dependabot
  module UpdateCheckers
    module Go
      class Dep
        class RequirementsUpdater
          class UnfixableRequirement < StandardError; end

          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-*]+)*/

          def initialize(requirements:, updated_source:, library:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements
            @updated_source = updated_source
            @library = library

            if latest_version && version_class.correct?(latest_version)
              @latest_version = version_class.new(latest_version)
            end

            return unless latest_resolvable_version
            return unless version_class.correct?(latest_resolvable_version)
            @latest_resolvable_version =
              version_class.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map do |req|
              req = req.merge(source: updated_source)
              next req unless latest_resolvable_version
              next initial_req_after_source_change(req) unless req[:requirement]

              next updated_library_requirement(req) if library?
              updated_app_requirement(req)
            end
          end

          private

          attr_reader :requirements, :updated_source,
                      :latest_version, :latest_resolvable_version

          def library?
            @library
          end

          def updating_from_git_to_version?
            return false unless updated_source&.fetch(:type) == "default"
            original_source = requirements.map { |r| r[:source] }.compact.first
            original_source&.fetch(:type) == "git"
          end

          def initial_req_after_source_change(req)
            return req unless updating_from_git_to_version?
            return req unless req[:requirement].nil?
            req.merge(requirement: "^#{latest_resolvable_version}")
          end

          def updated_library_requirement(req)
            current_requirement = req[:requirement]
            version = latest_resolvable_version

            ruby_reqs = ruby_requirements(current_requirement)
            return req if ruby_reqs.any? { |r| r.satisfied_by?(version) }

            reqs = current_requirement.strip.split(",").map(&:strip)

            updated_requirement =
              if current_requirement.include?("||")
                # Further widen the range by adding another OR condition
                current_requirement + " || ^#{version}"
              elsif reqs.any? { |r| r.match?(/(<|-\s)/) }
                # Further widen the range by updating the upper bound
                update_range_requirement(current_requirement)
              else
                # Convert existing requirement to a range
                create_new_range_requirement(reqs)
              end

            req.merge(requirement: updated_requirement)
          end

          def updated_app_requirement(req)
            current_requirement = req[:requirement]
            version = latest_resolvable_version

            ruby_reqs = ruby_requirements(current_requirement)
            reqs = current_requirement.strip.split(",").map(&:strip)

            if ruby_reqs.any? { |r| r.satisfied_by?(version) } &&
               current_requirement.match?(/(<|-\s|\|\|)/)
              return req
            end

            updated_requirement =
              if current_requirement.include?("||")
                # Further widen the range by adding another OR condition
                current_requirement + " || ^#{version}"
              elsif reqs.any? { |r| r.match?(/(<|-\s)/) }
                # Further widen the range by updating the upper bound
                update_range_requirement(current_requirement)
              else
                update_version_requirement(reqs)
              end

            req.merge(requirement: updated_requirement)
          end

          def ruby_requirements(requirement_string)
            requirement_class.requirements_array(requirement_string)
          end

          def update_range_requirement(req_string)
            range_requirement = req_string.split(",").
                                find { |r| r.match?(/<|(\s+-\s+)/) }

            versions = range_requirement.scan(VERSION_REGEX)
            upper_bound = versions.map { |v| version_class.new(v) }.max
            new_upper_bound = update_greatest_version(
              upper_bound,
              latest_resolvable_version
            )

            req_string.sub(
              upper_bound.to_s,
              new_upper_bound.to_s
            )
          end

          def create_new_range_requirement(string_reqs)
            version = latest_resolvable_version

            lower_bound =
              string_reqs.
              map { |req| requirement_class.new(req) }.
              flat_map { |req| req.requirements.map(&:last) }.
              min.to_s

            upper_bound =
              if string_reqs.first.start_with?("~") &&
                 version.to_s.split(".").count > 1
                create_upper_bound_for_tilda_req(string_reqs.first)
              else
                upper_bound_parts = [version.to_s.split(".").first.to_i + 1]
                upper_bound_parts.
                  fill("0", 1..(lower_bound.split(".").count - 1)).
                  join(".")
              end

            ">= #{lower_bound}, < #{upper_bound}"
          end

          def update_version_requirement(string_reqs)
            version = latest_resolvable_version.to_s.gsub(/^v/, "")
            current_req = string_reqs.first

            current_req.gsub(VERSION_REGEX, version)
          end

          def create_upper_bound_for_tilda_req(string_req)
            tilda_version = requirement_class.new(string_req).
                            requirements.map(&:last).
                            min.to_s

            upper_bound_parts = latest_resolvable_version.to_s.split(".")
            upper_bound_parts.slice(0, tilda_version.to_s.split(".").count)
            upper_bound_parts[-1] = "0"
            upper_bound_parts[-2] = (upper_bound_parts[-2].to_i + 1).to_s

            upper_bound_parts.join(".")
          end

          def update_greatest_version(old_version, version_to_be_permitted)
            version = version_class.new(old_version)
            version = version.release if version.prerelease?

            index_to_update =
              version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

            version.segments.map.with_index do |_, index|
              if index < index_to_update
                version_to_be_permitted.segments[index]
              elsif index == index_to_update
                version_to_be_permitted.segments[index] + 1
              else 0
              end
            end.join(".")
          end

          def version_class
            Utils::Go::Version
          end

          def requirement_class
            Utils::Go::Requirement
          end
        end
      end
    end
  end
end
