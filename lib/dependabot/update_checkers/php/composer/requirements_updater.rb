# frozen_string_literal: true

################################################################################
# For more details on Composer version constraints, see:                       #
# https://getcomposer.org/doc/articles/versions.md#writing-version-constraints #
################################################################################

require "dependabot/update_checkers/php/composer"
require "dependabot/update_checkers/php/composer/version"
require "dependabot/update_checkers/php/composer/requirement"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer
        class RequirementsUpdater
          ALIAS_REGEX = /[a-z0-9\-_\.]*\sas\s+/
          VERSION_REGEX = /(?:#{ALIAS_REGEX})?[0-9]+(?:\.[a-zA-Z0-9*\-]+)*/
          AND_SEPARATOR = /(?<=[a-zA-Z0-9*])(?<!\sas)[\s,]+(?![\s,]*[|-]|as)/
          OR_SEPARATOR = /(?<=[a-zA-Z0-9*])[\s,]*\|\|?\s*/
          SEPARATOR = /(?:#{AND_SEPARATOR})|(?:#{OR_SEPARATOR})/

          def initialize(requirements:, library:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements
            @library = library

            if latest_version
              @latest_version = version_class.new(latest_version)
            end

            return unless latest_resolvable_version
            @latest_resolvable_version =
              version_class.new(latest_resolvable_version)
          end

          # rubocop:disable Metrics/PerceivedComplexity
          def updated_requirements
            return requirements unless latest_resolvable_version

            requirements.map do |req|
              next req unless req[:requirement].match?(/\d/)
              next req if req[:requirement].include?("#")
              next updated_alias(req) if req[:requirement].match?(ALIAS_REGEX)
              next req if req_satisfied_by_latest_resolvable?(req[:requirement])

              if library?
                updated_library_requirement(req)
              else
                updated_app_requirement(req)
              end
            end
          end
          # rubocop:enable Metrics/PerceivedComplexity

          private

          attr_reader :requirements, :latest_version, :latest_resolvable_version

          def updated_alias(req)
            req_string = req[:requirement]
            real_version = req_string.split(/\sas\s/).first.strip

            # If the version we're aliasing isn't a version then we don't know
            # how to update it, so we just return the existing requirement.
            return req unless version_class.correct?(real_version)

            new_version_string = latest_resolvable_version.to_s
            new_req = req_string.sub(real_version, new_version_string)
            req.merge(requirement: new_req)
          end

          def library?
            @library
          end

          def updated_app_requirement(req)
            current_requirement = req[:requirement]
            reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)

            updated_requirement =
              if reqs.count > 1
                "^#{latest_resolvable_version}"
              elsif reqs.any? { |r| r.match?(/<|(\s+-\s+)/) }
                update_range_requirement(current_requirement)
              else
                update_version_string(current_requirement)
              end

            req.merge(requirement: updated_requirement)
          end

          def updated_library_requirement(req)
            current_requirement = req[:requirement]
            reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)

            updated_requirement =
              if reqs.any? { |r| r.start_with?("^") }
                update_caret_requirement(current_requirement)
              elsif reqs.any? { |r| r.start_with?("~") }
                update_tilda_requirement(current_requirement)
              elsif reqs.any? { |r| r.include?("*") }
                update_wildcard_requirement(current_requirement)
              elsif reqs.any? { |r| r.match?(/<|(\s+-\s+)/) }
                update_range_requirement(current_requirement)
              else
                update_version_string(current_requirement)
              end

            req.merge(requirement: updated_requirement)
          end

          def req_satisfied_by_latest_resolvable?(requirement_string)
            ruby_requirements(requirement_string).
              any? { |r| r.satisfied_by?(latest_resolvable_version) }
          end

          def update_version_string(req_string)
            req_string.
              sub(VERSION_REGEX) do |old_version|
                unless req_string.match?(/[~*\^]/)
                  next latest_resolvable_version.to_s
                end

                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i] == "*" ? "*" : part
                end.join(".")
              end
          end

          def ruby_requirements(requirement_string)
            requirement_string.strip.split(OR_SEPARATOR).map do |req_string|
              ruby_requirements =
                req_string.strip.split(AND_SEPARATOR).map do |r_string|
                  Composer::Requirement.new(r_string)
                end

              Composer::Requirement.new(ruby_requirements.join(",").split(","))
            end
          end

          def update_caret_requirement(req_string)
            caret_requirements =
              req_string.split(SEPARATOR).select { |r| r.start_with?("^") }
            version_parts = latest_resolvable_version.segments

            min_existing_precision =
              caret_requirements.map { |r| r.split(".").count }.min
            first_non_zero_index =
              version_parts.count.times.find { |i| version_parts[i] != 0 }

            precision = [min_existing_precision, first_non_zero_index + 1].max
            version = version_parts.first(precision).map.with_index do |part, i|
              i <= first_non_zero_index ? part : 0
            end.join(".")

            req_string + "|^#{version}"
          end

          def update_tilda_requirement(req_string)
            tilda_requirements =
              req_string.split(SEPARATOR).select { |r| r.start_with?("~") }
            precision = tilda_requirements.map { |r| r.split(".").count }.min

            version_parts = latest_resolvable_version.segments.first(precision)
            version_parts[-1] = 0
            version = version_parts.join(".")

            req_string + "|~#{version}"
          end

          def update_wildcard_requirement(req_string)
            wildcard_requirements =
              req_string.split(SEPARATOR).select { |r| r.include?("*") }
            precision = wildcard_requirements.map do |r|
              r.split(".").reject { |s| s == "*" }.count
            end.min
            wildcard_count = wildcard_requirements.map do |r|
              r.split(".").select { |s| s == "*" }.count
            end.min

            version_parts = latest_resolvable_version.segments.first(precision)
            version = version_parts.join(".")

            req_string + "|#{version}#{'.*' * wildcard_count}"
          end

          def update_range_requirement(req_string)
            range_requirements =
              req_string.split(SEPARATOR).select { |r| r.match?(/<|(\s+-\s+)/) }

            if range_requirements.count == 1
              range_requirement = range_requirements.first
              versions = range_requirement.scan(VERSION_REGEX)
              upper_bound = versions.map { |v| version_class.new(v) }.max
              new_upper_bound = update_greatest_version(
                upper_bound,
                latest_resolvable_version
              )

              req_string.sub(upper_bound.to_s, new_upper_bound.to_s)
            else
              req_string + "|^#{latest_resolvable_version}"
            end
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
            Composer::Version
          end
        end
      end
    end
  end
end
