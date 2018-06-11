# frozen_string_literal: true

require "dependabot/utils/elixir/version"
require "dependabot/utils/elixir/requirement"
require "dependabot/update_checkers/elixir/hex"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex
        class RequirementsUpdater
          OPERATORS = />=|<=|>|<|==|~>/
          AND_SEPARATOR = /\s+and\s+/
          OR_SEPARATOR = /\s+or\s+/
          SEPARATOR = /#{AND_SEPARATOR}|#{OR_SEPARATOR}/

          def initialize(requirements:, latest_resolvable_version:,
                         updated_source:)
            @requirements = requirements
            @updated_source = updated_source

            return unless latest_resolvable_version
            unless Utils::Elixir::Version.correct?(latest_resolvable_version)
              return
            end
            @latest_resolvable_version =
              Utils::Elixir::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map { |req| updated_mixfile_requirement(req) }
          end

          private

          attr_reader :requirements, :latest_resolvable_version, :updated_source

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable PerceivedComplexity
          def updated_mixfile_requirement(req)
            req = update_source(req)
            return req unless latest_resolvable_version && req[:requirement]
            return req if req_satisfied_by_latest_resolvable?(req[:requirement])

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
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable PerceivedComplexity

          def update_source(requirement_hash)
            # Only git sources ever need to be updated. Anything else should be
            # left alone.
            unless requirement_hash.dig(:source, :type) == "git"
              return requirement_hash
            end

            requirement_hash.merge(source: updated_source)
          end

          def req_satisfied_by_latest_resolvable?(requirement_string)
            ruby_requirements(requirement_string).
              any? { |r| r.satisfied_by?(latest_resolvable_version) }
          end

          def ruby_requirements(requirement_string)
            requirement_class.requirements_array(requirement_string)
          end

          def update_exact_version(previous_req, new_version)
            op = previous_req.match(OPERATORS).to_s
            old_version =
              Utils::Elixir::Version.new(previous_req.gsub(OPERATORS, ""))
            updated_version = at_same_precision(new_version, old_version)
            "#{op} #{updated_version}".strip
          end

          def update_twiddle_version(previous_req, new_version)
            previous_req = requirement_class.new(previous_req)
            old_version = previous_req.requirements.first.last
            updated_version = at_same_precision(new_version, old_version)
            requirement_class.new("~> #{updated_version}")
          end

          def update_mixfile_range(requirements)
            requirements = requirements.map { |r| requirement_class.new(r) }
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
                Utils::Elixir::Version.new(version_to_be_permitted)
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

            requirement_class.new("#{op} #{new_segments.join('.')}")
          end

          def binding_requirements(requirements)
            grouped_by_operator =
              requirements.group_by { |r| r.requirements.first.first }

            binding_reqs = grouped_by_operator.flat_map do |operator, reqs|
              case operator
              when "<", "<=" then reqs.min_by { |r| r.requirements.first.last }
              when ">", ">=" then reqs.max_by { |r| r.requirements.first.last }
              else requirements
              end
            end.uniq

            binding_reqs << requirement_class.new if binding_reqs.empty?
            binding_reqs.sort_by { |r| r.requirements.first.last }
          end

          def requirement_class
            Utils::Elixir::Requirement
          end
        end
      end
    end
  end
end
