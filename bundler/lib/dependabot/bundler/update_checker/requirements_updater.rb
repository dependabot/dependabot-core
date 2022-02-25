# frozen_string_literal: true

require "dependabot/bundler/update_checker"

module Dependabot
  module Bundler
    class UpdateChecker
      class RequirementsUpdater
        class UnfixableRequirement < StandardError; end

        ALLOWED_UPDATE_STRATEGIES =
          %i(bump_versions bump_versions_if_necessary).freeze

        def initialize(requirements:, update_strategy:, updated_source:,
                       latest_version:, latest_resolvable_version:)
          @requirements = requirements
          @latest_version = Gem::Version.new(latest_version) if latest_version
          @updated_source = updated_source
          @update_strategy = update_strategy

          check_update_strategy

          return unless latest_resolvable_version

          @latest_resolvable_version =
            Gem::Version.new(latest_resolvable_version)
        end

        def updated_requirements
          requirements.map do |req|
            if req[:file].match?(/\.gemspec/)
              update_gemspec_requirement(req)
            else
              # If a requirement doesn't come from a gemspec, it must be from
              # a Gemfile.
              update_gemfile_requirement(req)
            end
          end
        end

        private

        attr_reader :requirements, :updated_source,
                    :latest_version, :latest_resolvable_version,
                    :update_strategy

        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        def update_gemfile_requirement(req)
          req = req.merge(source: updated_source)
          return req unless latest_resolvable_version

          case update_strategy
          when :bump_versions
            update_version_requirement(req)
          when :bump_versions_if_necessary
            update_version_requirement_if_needed(req)
          else raise "Unexpected update strategy: #{update_strategy}"
          end
        end

        def update_version_requirement_if_needed(req)
          return req if new_version_satisfies?(req)

          update_version_requirement(req)
        end

        def update_version_requirement(req)
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
          release_precision = old_version.to_s.split(".").
                              take_while { |i| i.match?(/^\d+$/) }.count
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

        # rubocop:disable Metrics/PerceivedComplexity
        def update_gemspec_requirement(req)
          req = req.merge(source: updated_source) if req.fetch(:source)
          return req unless latest_version && latest_resolvable_version

          requirements =
            req[:requirement].split(",").map { |r| Gem::Requirement.new(r) }

          return req if requirements.all? do |r|
            requirement_satisfied?(r, req[:groups])
          end

          updated_requirements =
            requirements.flat_map do |r|
              next r if requirement_satisfied?(r, req[:groups])

              if req[:groups] == ["development"] then bumped_requirements(r)
              else
                widened_requirements(r)
              end
            end

          updated_requirements = binding_requirements(updated_requirements)
          req.merge(requirement: updated_requirements.map(&:to_s).join(", "))
        rescue UnfixableRequirement
          req.merge(requirement: :unfixable)
        end
        # rubocop:enable Metrics/PerceivedComplexity

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
            when "<", "<=" then reqs.min_by { |r| r.requirements.first.last }
            when ">", ">=" then reqs.max_by { |r| r.requirements.first.last }
            else requirements
            end
          end.uniq

          binding_reqs << Gem::Requirement.new if binding_reqs.empty?
          binding_reqs.sort_by { |r| r.requirements.first.last }
        end

        def widened_requirements(req)
          op, version = req.requirements.first

          case op
          when "=", nil
            if version < latest_resolvable_version
              [Gem::Requirement.new("#{op} #{latest_resolvable_version}")]
            else
              req
            end
          when "<", "<=" then [update_greatest_version(req, latest_version)]
          when "~>" then convert_twiddle_to_range(req, latest_version)
          when "!=" then []
          when ">", ">=" then raise UnfixableRequirement
          else raise "Unexpected operation for requirement: #{op}"
          end
        end

        def bumped_requirements(req)
          op, version = req.requirements.first

          case op
          when "=", nil
            if version < latest_resolvable_version
              [Gem::Requirement.new("#{op} #{latest_resolvable_version}")]
            else
              req
            end
          when "~>"
            [update_twiddle_version(req, latest_resolvable_version)]
          when "<", "<=" then [update_greatest_version(req, latest_version)]
          when "!=" then []
          when ">", ">=" then raise UnfixableRequirement
          else raise "Unexpected operation for requirement: #{op}"
          end
        end

        def convert_twiddle_to_range(requirement, version_to_be_permitted)
          version = requirement.requirements.first.last
          version = version.release if version.prerelease?

          index_to_update = [version.segments.count - 2, 0].max

          ub_segments = version_to_be_permitted.segments
          ub_segments << 0 while ub_segments.count <= index_to_update
          ub_segments = ub_segments[0..index_to_update]
          ub_segments[index_to_update] += 1

          lb_segments = version.segments
          lb_segments.pop while lb_segments.any? && lb_segments.last.zero?

          return [Gem::Requirement.new("< #{ub_segments.join('.')}")] if lb_segments.none?

          # Ensure versions have the same length as each other (cosmetic)
          length = [lb_segments.count, ub_segments.count].max
          lb_segments.fill(0, lb_segments.count...length)
          ub_segments.fill(0, ub_segments.count...length)

          [
            Gem::Requirement.new(">= #{lb_segments.join('.')}"),
            Gem::Requirement.new("< #{ub_segments.join('.')}")
          ]
        end

        # Updates the version in a "~>" constraint to allow the given version
        def update_twiddle_version(requirement, version_to_be_permitted)
          old_version = requirement.requirements.first.last
          updated_v = at_same_precision(version_to_be_permitted, old_version)
          Gem::Requirement.new("~> #{updated_v}")
        end

        # Updates the version in a "<" or "<=" constraint to allow the given
        # version
        def update_greatest_version(requirement, version_to_be_permitted)
          version_to_be_permitted = Gem::Version.new(version_to_be_permitted) if version_to_be_permitted.is_a?(String)
          op, version = requirement.requirements.first
          version = version.release if version.prerelease?

          index_to_update = [
            version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max,
            version_to_be_permitted.segments.count - 1
          ].min

          new_segments = version.segments.map.with_index do |_, index|
            if index < index_to_update
              version_to_be_permitted.segments[index]
            elsif index == index_to_update
              version_to_be_permitted.segments[index] + 1
            elsif index > version_to_be_permitted.segments.count - 1
              nil
            else
              0
            end
          end.compact

          Gem::Requirement.new("#{op} #{new_segments.join('.')}")
        end
      end
    end
  end
end
