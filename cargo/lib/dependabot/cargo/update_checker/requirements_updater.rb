# typed: true
# frozen_string_literal: true

################################################################################
# For more details on rust version constraints, see:                           #
# - https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html     #
# - https://steveklabnik.github.io/semver/semver/index.html                    #
################################################################################

require "sorbet-runtime"

require "dependabot/cargo/update_checker"
require "dependabot/cargo/requirement"
require "dependabot/cargo/version"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Cargo
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        class UnfixableRequirement < StandardError; end

        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-*]+)*/
        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            RequirementsUpdateStrategy::LockfileOnly,
            RequirementsUpdateStrategy::BumpVersions,
            RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        def initialize(requirements:, updated_source:, update_strategy:,
                       target_version:)
          @requirements = requirements
          @updated_source = updated_source
          @update_strategy = update_strategy

          check_update_strategy

          return unless target_version && version_class.correct?(target_version)

          @target_version = version_class.new(target_version)
        end

        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          # NOTE: Order is important here. The FileUpdater needs the updated
          # requirement at index `i` to correspond to the previous requirement
          # at the same index.
          requirements.map do |req|
            req = req.merge(source: updated_source)
            next req unless target_version
            next req if req[:requirement].nil?

            # TODO: Add a RequirementsUpdateStrategy::WidenRanges options
            if update_strategy == RequirementsUpdateStrategy::BumpVersionsIfNecessary
              update_version_requirement_if_needed(req)
            else
              update_version_requirement(req)
            end
          end
        end

        private

        attr_reader :requirements
        attr_reader :updated_source
        attr_reader :update_strategy
        attr_reader :target_version

        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        def update_version_requirement(req)
          string_reqs = req[:requirement].split(",").map(&:strip)

          new_requirement =
            if (exact_req = exact_req(string_reqs))
              # If there's an exact version, just return that
              # (it will dominate any other requirements)
              update_version_string(exact_req)
            elsif (req_to_update = non_range_req(string_reqs)) &&
                  update_version_string(req_to_update) != req_to_update
              # If a ~, ^, or * range needs to be updated, just return that
              # (it will dominate any other requirements)
              update_version_string(req_to_update)
            else
              # Otherwise, we must have a range requirement that needs
              # updating. Update it, but keep other requirements too
              update_range_requirements(string_reqs)
            end

          req.merge(requirement: new_requirement)
        end

        def update_version_requirement_if_needed(req)
          string_reqs = req[:requirement].split(",").map(&:strip)
          ruby_reqs = string_reqs.map { |r| Cargo::Requirement.new(r) }

          return req if ruby_reqs.all? { |r| r.satisfied_by?(target_version) }

          update_version_requirement(req)
        end

        def update_version_string(req_string)
          new_target_parts = target_version.to_s.sub(/\+.*/, "").split(".")
          req_string.sub(VERSION_REGEX) do |old_version|
            # For pre-release versions, just use the full version string
            next target_version.to_s if old_version.match?(/\d-/)

            old_parts = old_version.split(".")
            new_parts = new_target_parts.first(old_parts.count)
            new_parts.map.with_index do |part, i|
              old_parts[i] == "*" ? "*" : part
            end.join(".")
          end
        end

        def non_range_req(string_reqs)
          string_reqs.find { |r| r.include?("*") || r.match?(/^[\d~^]/) }
        end

        def exact_req(string_reqs)
          string_reqs.find { |r| Cargo::Requirement.new(r).exact? }
        end

        def update_range_requirements(string_reqs)
          string_reqs.map do |req|
            next req unless req.match?(/[<>]/)

            ruby_req = Cargo::Requirement.new(req)
            next req if ruby_req.satisfied_by?(target_version)

            raise UnfixableRequirement if req.start_with?(">")

            req.sub(VERSION_REGEX) do |old_version|
              if req.start_with?("<=")
                update_version_string(old_version)
              else
                update_greatest_version(old_version, target_version)
              end
            end
          end.join(", ")
        rescue UnfixableRequirement
          :unfixable
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
          Cargo::Version
        end
      end
    end
  end
end
