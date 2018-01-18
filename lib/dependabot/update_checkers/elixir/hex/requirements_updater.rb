# frozen_string_literal: true

require "dependabot/update_checkers/elixir/hex"
require "dependabot/update_checkers/elixir/hex/version"
require "dependabot/update_checkers/elixir/hex/requirement"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex
        class RequirementsUpdater
          OPERATORS = />=|<=|>|<|==|~>/
          AND_SEPARATOR = /\s+and\s+/
          OR_SEPARATOR = /\s+or\s+/
          SEPARATOR = /#{AND_SEPARATOR}|#{OR_SEPARATOR}/

          def initialize(requirements:, latest_resolvable_version:)
            @requirements = requirements

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Hex::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            return requirements unless latest_resolvable_version

            requirements.map do |req|
              next req if req_satisfied_by_latest_resolvable?(req[:requirement])
              updated_mixfile_requirement(req)
            end
          end

          private

          attr_reader :requirements, :latest_resolvable_version

          def req_satisfied_by_latest_resolvable?(requirement_string)
            ruby_requirements(requirement_string).
              any? { |r| r.satisfied_by?(latest_resolvable_version) }
          end

          def ruby_requirements(requirement_string)
            requirement_string.strip.split(OR_SEPARATOR).map do |req_string|
              ruby_requirements =
                req_string.strip.split(AND_SEPARATOR).map do |r_string|
                  Hex::Requirement.new(r_string)
                end

              Hex::Requirement.new(ruby_requirements.map(&:to_s))
            end
          end

          def updated_mixfile_requirement(req)
            return req unless latest_resolvable_version

            or_string_reqs = req[:requirement].split(OR_SEPARATOR)
            last_string_reqs = or_string_reqs.last.split(AND_SEPARATOR).
                               map(&:strip)

            new_requirement =
              if last_string_reqs.any? { |r| r.match(/^(?:\d|=)/) }
                exact_req = last_string_reqs.find { |r| r.match(/^(?:\d|=)/) }
                update_exact_version(exact_req, latest_resolvable_version).to_s
              elsif last_string_reqs.any? { |r| r.start_with?("~>") }
                tw_req = last_string_reqs.find { |r| r.start_with?("~>") }
                update_twiddle_version(tw_req, latest_resolvable_version).to_s
              else
                update_mixfile_range(last_string_reqs).map(&:to_s).join(" and ")
              end

            if or_string_reqs.count > 1
              new_requirement = req[:requirement] + " or " + new_requirement
            end

            req.merge(requirement: new_requirement)
          end

          def update_exact_version(previous_req, new_version)
            op = previous_req.match(OPERATORS).to_s
            old_version = Hex::Version.new(previous_req.gsub(OPERATORS, ""))
            updated_version = at_same_precision(new_version, old_version)
            "#{op} #{updated_version}".strip
          end

          def update_twiddle_version(previous_req, new_version)
            previous_req = Hex::Requirement.new(previous_req)
            old_version = previous_req.requirements.first.last
            updated_version = at_same_precision(new_version, old_version)
            Hex::Requirement.new("~> #{updated_version}")
          end

          def update_mixfile_range(requirements)
            requirements = requirements.map { |r| Hex::Requirement.new(r) }
            updated_requirements =
              requirements.flat_map do |r|
                next r if r.satisfied_by?(latest_resolvable_version)

                case op = r.requirements.first.first
                when "<", "<="
                  [update_greatest_version(r, latest_resolvable_version)]
                when "!="
                  []
                else
                  raise "Unexpected operation for unsatisfied Gemfile "\
                        "requirement: #{op}"
                end
              end

            binding_requirements(updated_requirements)
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

            Hex::Requirement.new("#{op} #{new_segments.join('.')}")
          end

          def binding_requirements(requirements)
            grouped_by_operator =
              requirements.group_by { |r| r.requirements.first.first }

            binding_reqs = grouped_by_operator.flat_map do |operator, reqs|
              case operator
              when "<", "<="
                reqs.sort_by { |r| r.requirements.first.last }.first
              when ">", ">="
                reqs.sort_by { |r| r.requirements.first.last }.last
              else requirements
              end
            end.uniq

            binding_reqs << Hex::Requirement.new if binding_reqs.empty?
            binding_reqs.sort_by { |r| r.requirements.first.last }
          end
        end
      end
    end
  end
end
