# typed: strict
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
require "dependabot/dependency_requirement"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Cargo
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        class UnfixableRequirement < StandardError; end

        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-*]+)*/
        PARTIAL_EQUALITY_REQUIREMENT = /\A\s*=\s*\d+(?:\.\d+)?\s*\z/
        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            Dependabot::RequirementsUpdateStrategy::LockfileOnly,
            Dependabot::RequirementsUpdateStrategy::BumpVersions,
            Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            updated_source: T.nilable(Dependabot::DependencyRequirement::ObjectHash),
            update_strategy: Dependabot::RequirementsUpdateStrategy,
            target_version: T.nilable(T.any(String, Gem::Version))
          ).void
        end
        def initialize(
          requirements:,
          updated_source:,
          update_strategy:,
          target_version:
        )
          @requirements = T.let(
            requirements.map { |req| Dependabot::DependencyRequirement.create(req) },
            T::Array[Dependabot::DependencyRequirement]
          )
          @updated_source = updated_source
          @update_strategy = update_strategy

          check_update_strategy

          return unless target_version && version_class.correct?(target_version)

          @target_version = T.let(version_class.new(target_version), Gem::Version)
        end

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          # NOTE: Order is important here. The FileUpdater needs the updated
          # requirement at index `i` to correspond to the previous requirement
          # at the same index.
          requirements.map do |req|
            req = Dependabot::DependencyRequirement.create(req.merge(source: updated_source))
            next req unless target_version
            next req if req.requirement.nil?

            # TODO: Add a RequirementsUpdateStrategy::WidenRanges options
            if update_strategy == Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary
              update_version_requirement_if_needed(req)
            else
              update_version_requirement(req)
            end
          end
        end

        private

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash)) }
        attr_reader :updated_source

        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :update_strategy

        sig { returns(T.nilable(Gem::Version)) }
        attr_reader :target_version

        sig { void }
        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        sig { params(req: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement) }
        def update_version_requirement(req)
          string_reqs = T.must(req.requirement_string).split(",").map(&:strip)

          new_requirement =
            if (exact_req = exact_req(string_reqs))
              # If there's an exact version, just return that
              # (it will dominate any other requirements)
              if exact_req.match?(PARTIAL_EQUALITY_REQUIREMENT)
                update_non_range_requirements(string_reqs, exact_req)
              else
                finalize_updated_requirements([update_version_string(exact_req)])
              end
            elsif (req_to_update = non_range_req(string_reqs)) &&
                  update_version_string(req_to_update) != req_to_update
              # If a ~, ^, or * range needs to be updated, just return that
              # (it will dominate any other requirements)
              update_non_range_requirements(string_reqs, req_to_update)
            else
              # Otherwise, we must have a range requirement that needs
              # updating. Update it, but keep other requirements too
              update_range_requirements(string_reqs)
            end

          Dependabot::DependencyRequirement.create(req.merge(requirement: new_requirement))
        end

        sig { params(req: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement) }
        def update_version_requirement_if_needed(req)
          string_reqs = T.must(req.requirement_string).split(",").map(&:strip)
          ruby_req = Dependabot::Cargo::Requirement.new(string_reqs)

          return req if ruby_req.satisfied_by?(T.must(target_version))

          update_version_requirement(req)
        rescue Gem::Requirement::BadRequirementError
          update_version_requirement(req)
        end

        sig { params(req_string: String).returns(String) }
        def update_version_string(req_string)
          new_target_parts = target_version.to_s.sub(/\+.*/, "").split(".")
          req_string.sub(VERSION_REGEX) do |old_version|
            # For pre-release versions, just use the full version string
            next target_version.to_s if old_version.match?(/\d-/)

            old_parts = old_version.split(".")
            new_parts = new_target_parts.first(old_parts.count)
            new_parts.map.with_index do |part, i|
              %w(* x X).include?(old_parts[i]) ? old_parts[i] : part
            end.join(".")
          end
        end

        sig { params(string_reqs: T::Array[String]).returns(T.nilable(String)) }
        def non_range_req(string_reqs)
          string_reqs.find { |req| wildcard_requirement?(req) || req.match?(/^[\d~^]/) }
        end

        sig { params(req: String).returns(T::Boolean) }
        def wildcard_requirement?(req)
          release = req.sub(/\A\s*[=~^]?\s*/, "").split(/[-+]/, 2).first
          T.must(release).split(".").intersect?(%w(* x X))
        end

        sig { params(string_reqs: T::Array[String]).returns(T.nilable(String)) }
        def exact_req(string_reqs)
          string_reqs.find do |req|
            req.match?(PARTIAL_EQUALITY_REQUIREMENT) || exact_requirement?(req)
          end
        end

        sig { params(req: String).returns(T::Boolean) }
        def exact_requirement?(req)
          Dependabot::Cargo::Requirement.new(req).exact?
        rescue Gem::Requirement::BadRequirementError
          false
        end

        sig do
          params(
            string_reqs: T::Array[String],
            req_to_update: String
          ).returns(T.any(String, Symbol))
        end
        def update_non_range_requirements(string_reqs, req_to_update)
          updated_req = update_version_string(req_to_update)
          return finalize_updated_requirements([updated_req]) unless T.must(target_version).prerelease?

          updated_reqs = string_reqs.map { |req| req == req_to_update ? updated_req : req }
          update_range_requirements(updated_reqs)
        end

        sig { params(string_reqs: T::Array[String]).returns(T.any(String, Symbol)) }
        def update_range_requirements(string_reqs)
          updated_reqs = string_reqs.map do |req|
            next req unless req.match?(/[<>]/)

            ruby_req = Dependabot::Cargo::Requirement.new(req)
            next req if ruby_req.bounds_satisfied_by?(T.must(target_version))

            raise UnfixableRequirement if req.start_with?(">")

            req.sub(VERSION_REGEX) do |old_version|
              if req.start_with?("<=")
                update_version_string(old_version)
              else
                update_greatest_version(old_version, T.must(target_version))
              end
            end
          end

          finalize_updated_requirements(updated_reqs)
        rescue Gem::Requirement::BadRequirementError, UnfixableRequirement
          :unfixable
        end

        sig { params(string_reqs: T::Array[String]).returns(T.any(String, Symbol)) }
        def finalize_updated_requirements(string_reqs)
          updated_reqs = add_prerelease_opt_in(string_reqs)
          requirement = Dependabot::Cargo::Requirement.new(updated_reqs)
          return updated_reqs.join(", ") if requirement.satisfied_by?(T.must(target_version))

          :unfixable
        rescue Gem::Requirement::BadRequirementError, UnfixableRequirement
          :unfixable
        end

        sig { params(string_reqs: T::Array[String]).returns(T::Array[String]) }
        def add_prerelease_opt_in(string_reqs)
          version = T.must(target_version)
          return string_reqs unless version.prerelease?

          requirement = Dependabot::Cargo::Requirement.new(string_reqs)
          return string_reqs if requirement.prerelease_opted_in?(version)

          lower_bound_index = string_reqs.index do |req|
            req.start_with?(">") && req.match?(/\d-[0-9A-Za-z-]/)
          end
          raise UnfixableRequirement unless lower_bound_index

          target = version.to_s.split("+", 2).first
          string_reqs.dup.tap { |reqs| reqs[lower_bound_index] = ">=#{target}" }
        end

        sig { params(old_version: String, version_to_be_permitted: Gem::Version).returns(String) }
        def update_greatest_version(old_version, version_to_be_permitted)
          version = version_class.new(old_version)
          version = version.release if version.prerelease?

          index_to_update =
            version.segments.map.with_index { |seg, i| seg.to_i.zero? ? 0 : i }.max

          version.segments.map.with_index do |_, index|
            if index < index_to_update
              version_to_be_permitted.segments[index]
            elsif index == index_to_update
              version_to_be_permitted.segments[index].to_i + 1
            else
              0
            end
          end.join(".")
        end

        sig { returns(T.class_of(Dependabot::Cargo::Version)) }
        def version_class
          Dependabot::Cargo::Version
        end
      end
    end
  end
end
