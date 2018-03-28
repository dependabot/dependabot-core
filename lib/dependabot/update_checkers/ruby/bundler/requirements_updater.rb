# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class RequirementsUpdater
          class UnfixableRequirement < StandardError; end

          def initialize(requirements:, library:, updated_source:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            @library = library

            @latest_version = Gem::Version.new(latest_version) if latest_version
            @updated_source = updated_source

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map do |req|
              if req[:file].match?(/\.gemspec/)
                updated_gemspec_requirement(req)
              else
                # If a requirement doesn't come from a gemspec, it must be from
                # a Gemfile.
                updated_gemfile_requirement(req)
              end
            end
          end

          private

          attr_reader :requirements, :updated_source,
                      :latest_version, :latest_resolvable_version

          def library?
            @library
          end

          def updated_gemfile_requirement(req)
            req = req.merge(source: updated_source)
            return req unless latest_resolvable_version
            return req if library? && new_version_satisfies?(req)

            requirements =
              req[:requirement].split(",").map { |r| Gem::Requirement.new(r) }

            new_requirement =
              if requirements.any?(&:exact?) then latest_resolvable_version.to_s
              elsif requirements.any? { |r| r.to_s.start_with?("~>") }
                tw_req = requirements.find { |r| r.to_s.start_with?("~>") }
                update_twiddle_version(tw_req, latest_resolvable_version).to_s
              else
                update_gemfile_range(requirements).map(&:to_s).join(", ")
              end

            req.merge(requirement: new_requirement)
          end

          def new_version_satisfies?(req)
            original_req = Gem::Requirement.new(req[:requirement].split(","))
            original_req.satisfied_by?(latest_resolvable_version)
          end

          def update_gemfile_range(requirements)
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
            release_precision =
              old_version.to_s.split(".").select { |i| i.match?(/^\d+$/) }.count
            prerelease_precision =
              old_version.to_s.split(".").count - release_precision

            new_release =
              new_version.to_s.split(".").first(release_precision)
            new_prerelease =
              new_version.to_s.split(".").
              drop_while { |i| i.match?(/^\d+$/) }.
              first([prerelease_precision, 1].max)

            [*new_release, *new_prerelease].join(".")
          end

          def updated_gemspec_requirement(req)
            return req unless latest_version

            requirements =
              req[:requirement].split(",").map { |r| Gem::Requirement.new(r) }

            return req if requirements.all? do |r|
              requirement_satisfied?(r, req[:groups])
            end

            updated_requirements =
              requirements.flat_map do |r|
                next r if requirement_satisfied?(r, req[:groups])

                if req[:groups] == ["development"]
                  fixed_development_requirements(r)
                else
                  fixed_requirements(r)
                end
              end

            updated_requirements = binding_requirements(updated_requirements)
            req.merge(requirement: updated_requirements.map(&:to_s).join(", "))
          rescue UnfixableRequirement
            req.merge(requirement: :unfixable)
          end

          def requirement_satisfied?(req, groups)
            if groups == ["development"]
              req.satisfied_by?(latest_resolvable_version)
            else
              req.satisfied_by?(latest_version)
            end
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

            binding_reqs << Gem::Requirement.new if binding_reqs.empty?
            binding_reqs.sort_by { |r| r.requirements.first.last }
          end

          def fixed_requirements(req)
            op, version = req.requirements.first

            case op
            when "=", nil then [Gem::Requirement.new(">= #{version}")]
            when "<", "<=" then [update_greatest_version(req, latest_version)]
            when "~>" then convert_twidle_to_range(req, latest_version)
            when "!=" then []
            when ">", ">=" then raise UnfixableRequirement
            else raise "Unexpected operation for requirement: #{op}"
            end
          end

          def fixed_development_requirements(req)
            op = req.requirements.first.first

            case op
            when "=", nil
              [Gem::Requirement.new("#{op} #{latest_resolvable_version}")]
            when "~>"
              [update_twiddle_version(req, latest_resolvable_version)]
            when "<", "<=" then [update_greatest_version(req, latest_version)]
            when "!=" then []
            when ">", ">=" then raise UnfixableRequirement
            else raise "Unexpected operation for requirement: #{op}"
            end
          end

          # rubocop:disable Metrics/AbcSize
          def convert_twidle_to_range(requirement, version_to_be_permitted)
            version = requirement.requirements.first.last
            version = version.release if version.prerelease?

            index_to_update = [version.segments.count - 2, 0].max

            ub_segments = version_to_be_permitted.segments
            ub_segments << 0 while ub_segments.count <= index_to_update
            ub_segments = ub_segments[0..index_to_update]
            ub_segments[index_to_update] += 1

            lb_segments = version.segments
            lb_segments.pop while lb_segments.any? && lb_segments.last.zero?

            if lb_segments.none?
              return [Gem::Requirement.new("< #{ub_segments.join('.')}")]
            end

            # Ensure versions have the same length as each other (cosmetic)
            length = [lb_segments.count, ub_segments.count].max
            lb_segments.fill(0, lb_segments.count...length)
            ub_segments.fill(0, ub_segments.count...length)

            [
              Gem::Requirement.new(">= #{lb_segments.join('.')}"),
              Gem::Requirement.new("< #{ub_segments.join('.')}")
            ]
          end
          # rubocop:enable Metrics/AbcSize

          # Updates the version in a "~>" constraint to allow the given version
          def update_twiddle_version(requirement, version_to_be_permitted)
            old_version = requirement.requirements.first.last
            updated_v = at_same_precision(version_to_be_permitted, old_version)
            Gem::Requirement.new("~> #{updated_v}")
          end

          # Updates the version in a "<" or "<=" constraint to allow the given
          # version
          def update_greatest_version(requirement, version_to_be_permitted)
            if version_to_be_permitted.is_a?(String)
              version_to_be_permitted =
                Gem::Version.new(version_to_be_permitted)
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
