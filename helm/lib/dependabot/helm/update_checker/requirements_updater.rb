# typed: strict
# frozen_string_literal: true

################################################################################
# Helm Chart.yaml dependency constraints use SemVer ranges (Masterminds), the  #
# same family npm uses. This mirrors                                           #
# Dependabot::NpmAndYarn::UpdateChecker::RequirementsUpdater, scoped to the     #
# three strategies Helm supports, with the git-source / JSR branches removed.   #
################################################################################

require "sorbet-runtime"

require "dependabot/dependency_requirement"
require "dependabot/helm/requirement"
require "dependabot/helm/update_checker"
require "dependabot/helm/version"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Helm
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        # Possessive quantifiers (++) keep these linear on pathological input
        # (no catastrophic/polynomial backtracking) while matching identically
        # to the greedy forms for real version constraints. The trailing group
        # consumes an optional '+<build metadata/digest>' suffix so rewrites
        # replace it wholesale instead of leaving a stale suffix behind
        # (e.g. "1.2.3+old" -> "1.5.0", not "1.5.0+old").
        VERSION_REGEX = /[0-9]++(?:\.[A-Za-z0-9\-_]++)*+(?:\+[A-Za-z0-9\-_.]++)?/
        SEPARATOR = /(?<=[a-zA-Z0-9*])[\s|]++(?![\s|-])/
        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            RequirementsUpdateStrategy::LockfileOnly,
            RequirementsUpdateStrategy::WidenRanges,
            RequirementsUpdateStrategy::BumpVersions,
            RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            update_strategy: Dependabot::RequirementsUpdateStrategy,
            latest_resolvable_version: T.nilable(T.any(String, Gem::Version))
          ).void
        end
        def initialize(requirements:, update_strategy:, latest_resolvable_version:)
          @requirements = requirements
          @update_strategy = update_strategy

          check_update_strategy

          return unless latest_resolvable_version

          @latest_resolvable_version = T.let(
            version_class.new(latest_resolvable_version),
            Dependabot::Version
          )
        end

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          requirements.map do |req|
            next req unless latest_resolvable_version
            next req unless req[:requirement]
            # Leave dist-tags / non-numeric leading tokens untouched.
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

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(Dependabot::RequirementsUpdateStrategy) }
        attr_reader :update_strategy

        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :latest_resolvable_version

        sig { void }
        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        sig { params(req: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement) }
        def update_version_requirement(req)
          current_requirement = req[:requirement]

          if current_requirement.match?(/(<|-\s)/i)
            # Check every OR alternative, not just the first — a later branch may
            # already permit the latest version.
            return req if ruby_requirements(current_requirement).any? { |r| r.satisfied_by?(latest_resolvable_version) }

            updated_req = update_range_requirement(current_requirement)
            return T.cast(req.merge(requirement: updated_req), Dependabot::DependencyRequirement)
          end

          reqs = current_requirement.strip.split(SEPARATOR).map(&:strip)
          T.cast(req.merge(requirement: update_version_string(reqs.first)), Dependabot::DependencyRequirement)
        end

        sig { params(req: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement) }
        def update_version_requirement_if_needed(req)
          current_requirement = req[:requirement]
          version = latest_resolvable_version
          return req if current_requirement.strip == ""

          ruby_reqs = ruby_requirements(current_requirement)
          return req if ruby_reqs.any? { |r| r.satisfied_by?(version) }

          update_version_requirement(req)
        end

        sig { params(req: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement) }
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
            elsif reqs.one?
              update_version_string(current_requirement)
            else
              # An OR of caret/tilde/exact alternatives, none of which permit the
              # latest version: widen by adding a new alternative rather than
              # rewriting the authored ones (npm's widen_ranges behavior).
              "#{current_requirement} || ^#{latest_resolvable_version}"
            end

          T.cast(req.merge(requirement: updated_requirement), Dependabot::DependencyRequirement)
        end

        sig { params(requirement_string: String).returns(T::Array[Helm::Requirement]) }
        def ruby_requirements(requirement_string)
          Helm::Requirement.requirements_array(requirement_string)
        end

        sig { params(req_string: String).returns(String) }
        def update_range_requirement(req_string)
          range_requirements =
            req_string.split(SEPARATOR).select { |r| r.match?(/<|(\s++-\s++)/) }

          if range_requirements.one?
            range_requirement = T.must(range_requirements.first)
            versions = range_requirement.scan(VERSION_REGEX)
            version_objects = versions.map { |v| version_class.new(v.to_s) }
            upper_bound = T.must(version_objects.max)
            new_upper_bound = update_greatest_version(
              upper_bound.to_s,
              T.must(latest_resolvable_version)
            )

            req_string.sub(
              upper_bound.to_s,
              new_upper_bound.to_s
            )
          else
            req_string + " || ^#{T.must(latest_resolvable_version)}"
          end
        end

        sig { params(req_string: String).returns(String) }
        def update_version_string(req_string)
          latest = T.must(latest_resolvable_version).to_s
          req_string
            .sub(VERSION_REGEX) do |old_version|
              if old_version.match?(/\d-/) || latest.match?(/\d-/)
                latest
              else
                old_parts = old_version.split(".")
                new_parts = latest.split(".")
                                  .first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i]&.match?(/^x\b/) ? "x" : part
                end.join(".")
              end
            end
        end

        sig { params(old_version: String, version_to_be_permitted: Dependabot::Version).returns(String) }
        def update_greatest_version(old_version, version_to_be_permitted)
          version = version_class.new(old_version)
          version = version.release if version.prerelease?

          index_to_update =
            version.segments.map.with_index { |seg, i| T.cast(seg, Integer).zero? ? 0 : i }.max || 0

          version.segments.map.with_index do |_, index|
            segment_value =
              if index < index_to_update
                T.cast(version_to_be_permitted.segments[index], Integer)
              elsif index == index_to_update
                T.cast(version_to_be_permitted.segments[index], Integer) + 1
              else
                0
              end
            segment_value.to_s
          end.join(".")
        end

        sig { returns(T.class_of(Helm::Version)) }
        def version_class
          Helm::Version
        end
      end
    end
  end
end
