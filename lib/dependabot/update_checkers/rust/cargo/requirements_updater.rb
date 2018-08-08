# frozen_string_literal: true

################################################################################
# For more details on rust version constraints, see:                           #
# - https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html     #
# - https://steveklabnik.github.io/semver/semver/index.html                    #
################################################################################

require "dependabot/update_checkers/rust/cargo"
require "dependabot/utils/rust/requirement"
require "dependabot/utils/rust/version"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo
        class RequirementsUpdater
          class UnfixableRequirement < StandardError; end

          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-*]+)*/
          ALLOWED_UPDATE_STRATEGIES =
            %i(bump_versions bump_versions_if_needed).freeze

          def initialize(requirements:, updated_source:, update_strategy:,
                         library:, latest_version:, latest_resolvable_version:)
            @requirements = requirements
            @updated_source = updated_source
            @update_strategy = update_strategy
            @library = library

            check_update_strategy

            if latest_version && version_class.correct?(latest_version)
              @latest_version = version_class.new(latest_version)
            end

            return unless latest_resolvable_version
            return unless version_class.correct?(latest_resolvable_version)
            @latest_resolvable_version =
              version_class.new(latest_resolvable_version)
          end

          def updated_requirements
            # Note: Order is important here. The FileUpdater needs the updated
            # requirement at index `i` to correspond to the previous requirement
            # at the same index.
            requirements.map do |req|
              req = req.merge(source: updated_source)
              next req unless latest_resolvable_version
              next req if req[:requirement].nil?

              # TODO: Add a widen_ranges options
              if update_strategy == :bump_versions_if_needed
                update_version_requirement_if_needed(req)
              else
                update_version_requirement(req)
              end
            end
          end

          private

          attr_reader :requirements, :updated_source, :update_strategy,
                      :latest_version, :latest_resolvable_version

          def library?
            @library
          end

          def check_update_strategy
            return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)
            raise "Unknown update strategy: #{update_strategy}"
          end

          def target_version
            library? ? latest_version : latest_resolvable_version
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
            ruby_reqs = string_reqs.map { |r| Utils::Rust::Requirement.new(r) }

            return req if ruby_reqs.all? { |r| r.satisfied_by?(target_version) }

            update_version_requirement(req)
          end

          def update_version_string(req_string)
            req_string.sub(VERSION_REGEX) do |old_version|
              # For pre-release versions, just use the full version string
              next target_version.to_s if old_version.match?(/\d-/)

              old_parts = old_version.split(".")
              new_parts = target_version.to_s.split(".").
                          first(old_parts.count)
              new_parts.map.with_index do |part, i|
                old_parts[i] == "*" ? "*" : part
              end.join(".")
            end
          end

          def non_range_req(string_reqs)
            string_reqs.find { |r| r.include?("*") || r.match?(/^[\d~^]/) }
          end

          def exact_req(string_reqs)
            string_reqs.find { |r| Utils::Rust::Requirement.new(r).exact? }
          end

          def update_range_requirements(string_reqs)
            string_reqs.map do |req|
              next req unless req.match?(/[<>]/)
              ruby_req = Utils::Rust::Requirement.new(req)
              next req if ruby_req.satisfied_by?(target_version)

              raise UnfixableRequirement if req.start_with?(">")

              req.sub(VERSION_REGEX) do |old_version|
                update_greatest_version(old_version, target_version)
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
              else 0
              end
            end.join(".")
          end

          def version_class
            Utils::Rust::Version
          end
        end
      end
    end
  end
end
