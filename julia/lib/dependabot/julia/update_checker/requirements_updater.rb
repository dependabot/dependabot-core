# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_requirement"
require "dependabot/julia/requirement"
require "dependabot/julia/version"

module Dependabot
  module Julia
    class RequirementsUpdater
      extend T::Sig

      # Julia compat entries only accept plain, dot-separated numeric versions
      # of at most three parts (see Pkg's `semver_spec`), so anything a version
      # string carries beyond "major.minor.patch" has to be dropped before it
      # can be suggested as a bound. This matters for JLL packages, which
      # register build metadata as part of the version ("1.6.10+0"): writing
      # `Zlib_jll = "1.6.10+0"` into [compat] makes Pkg reject the Project.toml.
      NUMERIC_VERSION_PREFIX = /\A\d+(?:\.\d+){0,2}/

      sig do
        params(
          requirements: T::Array[Dependabot::DependencyRequirement],
          target_version: T.nilable(String),
          update_strategy: T.nilable(Symbol)
        ).void
      end
      def initialize(requirements:, target_version:, update_strategy:)
        @requirements = T.let(
          requirements.map { |req| Dependabot::DependencyRequirement.create(req) },
          T::Array[Dependabot::DependencyRequirement]
        )
        @target_version = target_version
        # Julia's ecosystem convention (CompatHelper) is to append a new spec
        # to the existing compat entry, i.e. widen, so that is the default.
        @update_strategy = T.let(update_strategy || :widen_ranges, Symbol)
      end

      sig { returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        return requirements unless target_version
        return requirements if update_strategy == :lockfile_only

        target_version_obj = Dependabot::Julia::Version.new(target_version)

        requirements.map do |requirement|
          update_requirement(requirement, target_version_obj)
        end
      end

      private

      sig { returns(T::Array[Dependabot::DependencyRequirement]) }
      attr_reader :requirements

      sig { returns(T.nilable(String)) }
      attr_reader :target_version

      sig { returns(Symbol) }
      attr_reader :update_strategy

      sig do
        params(
          requirement: Dependabot::DependencyRequirement,
          target_version: Dependabot::Julia::Version
        ).returns(Dependabot::DependencyRequirement)
      end
      def update_requirement(requirement, target_version)
        current_requirement = requirement.requirement_string

        # If requirement is nil (no compat entry), use target version
        new_requirement = if current_requirement.nil?
                            exact_version_spec(target_version)
                          else
                            updated_version_requirement(current_requirement, target_version)
                          end

        Dependabot::DependencyRequirement.create(requirement.merge(requirement: new_requirement))
      end

      sig { params(requirement_string: String, target_version: Dependabot::Julia::Version).returns(String) }
      def updated_version_requirement(requirement_string, target_version)
        # Don't update range requirements (e.g., "0.34 - 0.35") - these are explicit manual constraints
        return requirement_string if requirement_string.match?(Dependabot::Julia::Requirement::HYPHEN_RANGE_PATTERN)

        # Parse all constraints in the requirement string
        reqs = Dependabot::Julia::Requirement.requirements_array(requirement_string)

        # Check if any requirement is satisfied by the target version
        # Note: This uses the implicit caret semantics from the Requirement class
        satisfied = reqs.any? { |req| req.satisfied_by?(target_version) }

        case update_strategy
        when :bump_versions
          simplified_version_spec(target_version)
        when :bump_versions_if_necessary
          satisfied ? requirement_string : simplified_version_spec(target_version)
        else # :widen_ranges
          satisfied ? requirement_string : append_spec(requirement_string, target_version)
        end
      end

      sig { params(requirement_string: String, target_version: Dependabot::Julia::Version).returns(String) }
      def append_spec(requirement_string, target_version)
        # Append a new requirement that includes the target version
        # Following CompatHelper.jl's approach: use major.minor for versions >= 1.0,
        # 0.minor for 0.x versions, and 0.0.patch for 0.0.x versions
        new_spec = simplified_version_spec(target_version)

        # Append the new spec to the existing requirement (CompatHelper KeepEntry behavior)
        # Detect whether the existing requirement uses spaces after commas and preserve that format
        # and default to ", " if no commas found
        separator = requirement_string.include?(",") && !requirement_string.include?(", ") ? "," : ", "
        "#{requirement_string}#{separator}#{new_spec}"
      end

      # The target version rendered as an exact compat bound, e.g. "1.6.10+0"
      # (a JLL build) becomes "1.6.10", which still admits the build.
      sig { params(target_version: Dependabot::Julia::Version).returns(String) }
      def exact_version_spec(target_version)
        version_string = target_version.to_s
        version_string[NUMERIC_VERSION_PREFIX] || version_string
      end

      sig { params(target_version: Dependabot::Julia::Version).returns([Integer, Integer, Integer]) }
      def compat_version_parts(target_version)
        parts = exact_version_spec(target_version).split(".")
        [parts[0].to_i, parts[1].to_i, parts[2].to_i]
      end

      sig { params(target_version: Dependabot::Julia::Version).returns(String) }
      def simplified_version_spec(target_version)
        # Follow CompatHelper.jl's compat_version_number logic:
        # - major > 0: use "major.minor"
        # - major == 0, minor > 0: use "0.minor"
        # - major == 0, minor == 0: use "0.0.patch"
        # Note: CompatHelper always returns plain versions (no ^ or ~ prefix)
        major, minor, patch = compat_version_parts(target_version)

        if major.positive?
          "#{major}.#{minor}"
        elsif minor.positive?
          "0.#{minor}"
        else
          "0.0.#{patch}"
        end
      end
    end
  end
end
