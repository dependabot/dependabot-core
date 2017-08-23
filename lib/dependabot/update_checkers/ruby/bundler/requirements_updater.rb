# frozen_string_literal: true
require "gemnasium/parser"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        class RequirementsUpdater
          class UnfixableRequirement < StandardError; end

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
            requirements.map do |req|
              case req[:file]
              when "Gemfile" then updated_gemfile_requirement(req)
              when /\.gemspec/ then updated_gemspec_requirement(req)
              else raise "Unexpected file name: #{req[:file]}"
              end
            end
          end

          private

          def updated_gemfile_requirement(req)
            return req unless latest_resolvable_version

            original_req = Gem::Requirement.new(req[:requirement].split(","))

            if original_req.satisfied_by?(latest_resolvable_version) &&
               (existing_version.nil? ||
               latest_resolvable_version <= existing_version)
              return req
            end

            new_req = req[:requirement].gsub(/<=?/, "~>")
            new_req.sub!(Gemnasium::Parser::Patterns::VERSION) do |old_version|
              at_same_precision(latest_resolvable_version, old_version)
            end

            req.dup.merge(requirement: new_req)
          end

          def at_same_precision(new_version, old_version)
            precision = old_version.to_s.split(".").count
            new_version.to_s.split(".").first(precision).join(".")
          end

          def updated_gemspec_requirement(req)
            return req unless latest_version

            requirements =
              req[:requirement].split(",").map { |r| Gem::Requirement.new(r) }

            if requirements.all? { |r| r.satisfied_by?(latest_version) }
              return req
            end

            updated_requirements =
              requirements.flat_map do |r|
                next r if r.satisfied_by?(latest_version)
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

          def binding_requirements(requirements)
            grouped_by_operator =
              requirements.uniq.group_by { |r| r.requirements.first.first }

            binding_reqs = grouped_by_operator.flat_map do |operator, reqs|
              case operator
              when "<", "<="
                reqs.sort_by { |r| r.requirements.first.last }.first
              when ">", ">="
                reqs.sort_by { |r| r.requirements.first.last }.last
              else requirements
              end
            end

            binding_reqs.sort_by { |r| r.requirements.first.last }
          end

          def fixed_requirements(r)
            op, version = r.requirements.first

            case op
            when "=", nil then [Gem::Requirement.new(">= #{version}")]
            when "<", "<=" then [updated_greatest_version(r)]
            when "~>" then updated_twidle_requirements(r)
            when "!=", ">", ">=" then raise UnfixableRequirement
            else raise "Unexpected operation for requirement: #{op}"
            end
          end

          def fixed_development_requirements(r)
            op, version = r.requirements.first

            case op
            when "=", nil then [Gem::Requirement.new("#{op} #{latest_version}")]
            when "<", "<=" then [updated_greatest_version(r)]
            when "~>" then
              updated_version = at_same_precision(latest_version, version)
              [Gem::Requirement.new("~> #{updated_version}")]
            when "!=", ">", ">=" then raise UnfixableRequirement
            else raise "Unexpected operation for requirement: #{op}"
            end
          end

          # rubocop:disable Metrics/AbcSize
          def updated_twidle_requirements(requirement)
            version = requirement.requirements.first.last
            version = version.release if version.prerelease?

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
          # rubocop:enable Metrics/AbcSize

          # Updates the version in a "<" or "<=" constraint to allow the latest
          # version
          def updated_greatest_version(requirement)
            op, version = requirement.requirements.first
            version = version.release if version.prerelease?

            index_to_update =
              version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

            new_segments = version.segments.map.with_index do |_, index|
              if index < index_to_update
                latest_version.segments[index]
              elsif index == index_to_update
                latest_version.segments[index] + 1
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
