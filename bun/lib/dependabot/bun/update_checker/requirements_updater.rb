# typed: true
# frozen_string_literal: true

################################################################################
# For more details on npm version constraints, see:                            #
# https://docs.npmjs.com/misc/semver                                           #
################################################################################

require "dependabot/npm_and_yarn/requirement"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/version"
require "dependabot/requirements_update_strategy"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      class RequirementsUpdater
        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/
        SEPARATOR = /(?<=[a-zA-Z0-9*])[\s|]+(?![\s|-])/
        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            RequirementsUpdateStrategy::LockfileOnly,
            RequirementsUpdateStrategy::WidenRanges,
            RequirementsUpdateStrategy::BumpVersions,
            RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        def initialize(requirements:, updated_source:, update_strategy:,
                       latest_resolvable_version:)
          @requirements = requirements
          @updated_source = updated_source
          @update_strategy = update_strategy

          check_update_strategy

          return unless latest_resolvable_version

          @latest_resolvable_version =
            version_class.new(latest_resolvable_version)
        end

        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          requirements.map do |req|
            req = req.merge(source: updated_source)
            next req unless latest_resolvable_version
            next initial_req_after_source_change(req) unless req[:requirement]
            next req if req[:requirement].match?(/^([A-Za-uw-z]|v[^\d])/)

            case update_strategy
            when RequirementsUpdateStrategy::WidenRanges then widen_requirement(req)
            when RequirementsUpdateStrategy::BumpVersions then update_version_requirement(req)
            when RequirementsUpdateStrategy::BumpVersionsIfNecessary
              update_version_requirement_if_needed(req)
            else raise "Unexpected update strategy: #{update_strategy}"
            end
          end
        end

        private

        attr_reader :requirements
        attr_reader :updated_source
        attr_reader :update_strategy
        attr_reader :latest_resolvable_version

        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        def updating_from_git_to_npm?
          return false unless updated_source.nil?

          original_source = requirements.filter_map { |r| r[:source] }.first
          original_source&.fetch(:type) == "git"
        end

        def initial_req_after_source_change(req)
          return req unless updating_from_git_to_npm?
          return req unless req[:requirement].nil?

          req.merge(requirement: "^#{latest_resolvable_version}")
        end

        def update_version_requirement(req)
          current_requirement = req[:requirement]

          if current_requirement.match?(/(<|-\s)/i)
            ruby_req = ruby_requirements(current_requirement).first
            return req if ruby_req.satisfied_by?(latest_resolvable_version)

            updated_req = update_range_requirement(current_requirement)
            return req.merge(requirement: updated_req)
          end

          reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)
          req.merge(requirement: update_version_string(reqs.first))
        end

        def update_version_requirement_if_needed(req)
          current_requirement = req[:requirement]
          version = latest_resolvable_version
          return req if current_requirement.strip == ""

          ruby_reqs = ruby_requirements(current_requirement)
          return req if ruby_reqs.any? { |r| r.satisfied_by?(version) }

          update_version_requirement(req)
        end

        def widen_requirement(req)
          current_requirement = req[:requirement]
          version = latest_resolvable_version
          return req if current_requirement.strip == ""

          ruby_reqs = ruby_requirements(current_requirement)
          return req if ruby_reqs.any? { |r| r.satisfied_by?(version) }

          reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)

          updated_requirement =
            if reqs.any? { |r| r.match?(/(<|-\s)/i) }
              update_range_requirement(current_requirement)
            elsif current_requirement.strip.split(SEPARATOR).count == 1
              update_version_string(current_requirement)
            else
              current_requirement
            end

          req.merge(requirement: updated_requirement)
        end

        def ruby_requirements(requirement_string)
          NpmAndYarn::Requirement
            .requirements_array(requirement_string)
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

            req_string.sub(
              upper_bound.to_s,
              new_upper_bound.to_s
            )
          else
            req_string + " || ^#{latest_resolvable_version}"
          end
        end

        def update_version_string(req_string)
          req_string
            .sub(VERSION_REGEX) do |old_version|
              if old_version.match?(/\d-/) ||
                 latest_resolvable_version.to_s.match?(/\d-/)
                latest_resolvable_version.to_s
              else
                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".")
                                                     .first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i].match?(/^x\b/) ? "x" : part
                end.join(".")
              end
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
            else
              0
            end
          end.join(".")
        end

        def version_class
          NpmAndYarn::Version
        end
      end
    end
  end
end
