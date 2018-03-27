# frozen_string_literal: true

################################################################################
# For more details on rust version constraints, see:                           #
# - https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html     #
# - https://steveklabnik.github.io/semver/semver/index.html                    #
################################################################################

require "dependabot/update_checkers/rust/cargo"
require "dependabot/update_checkers/rust/cargo/requirement"
require "dependabot/update_checkers/rust/cargo/version"

module Dependabot
  module UpdateCheckers
    module Rust
      class Cargo
        class RequirementsUpdater
          class UnfixableRequirement < StandardError; end

          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_*]+)*/

          def initialize(requirements:, library:, latest_version:)
            @requirements = requirements
            @library = library
            return unless latest_version
            @latest_version = Cargo::Version.new(latest_version)
          end

          def updated_requirements
            return requirements unless latest_version

            requirements.map do |req|
              next req if req[:requirement].nil?

              if library?
                nil
              else
                updated_app_requirement(req)
              end
            end
          end

          private

          attr_reader :requirements, :latest_version

          def library?
            @library
          end

          def updated_app_requirement(req)
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

          def update_version_string(req_string)
            req_string.sub(VERSION_REGEX) do |old_version|
              if old_version.match?(/\d-/)
                # For pre-release versions, just use the full version string
                latest_version.to_s
              else
                old_parts = old_version.split(".")
                new_parts = latest_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i] == "*" ? "*" : part
                end.join(".")
              end
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
              next req if ruby_req.satisfied_by?(latest_version)

              raise UnfixableRequirement if req.start_with?(">")

              req.sub(VERSION_REGEX) do |old_version|
                update_greatest_version(old_version, latest_version)
              end
            end.join(", ")
          rescue UnfixableRequirement
            req.merge(requirement: :unfixable)
          end

          def update_greatest_version(old_version, version_to_be_permitted)
            version = Cargo::Version.new(old_version)
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
        end
      end
    end
  end
end
