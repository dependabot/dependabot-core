# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_requirement"
require "dependabot/julia/requirement"
require "dependabot/julia/version"

module Dependabot
  module Julia
    class RequirementsUpdater
      extend T::Sig

      sig do
        params(
          requirements: T::Array[Dependabot::DependencyRequirement],
          target_version: T.nilable(String),
          update_strategy: T.nilable(Symbol),
          stdlib_versions: T::Hash[String, T::Array[String]]
        ).void
      end
      def initialize(requirements:, target_version:, update_strategy:, stdlib_versions: {})
        @requirements = T.let(
          requirements.map { |req| Dependabot::DependencyRequirement.create(req) },
          T::Array[Dependabot::DependencyRequirement]
        )
        @target_version = target_version
        # Julia's ecosystem convention (CompatHelper) is to append a new spec
        # to the existing compat entry, i.e. widen, so that is the default.
        @update_strategy = T.let(update_strategy || :widen_ranges, Symbol)
        # For a standard library: the versions its compat entry has to admit,
        # keyed by project file (see FileParser#dependency_metadata)
        @stdlib_versions = stdlib_versions
      end

      sig { returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        return requirements if update_strategy == :lockfile_only

        target_version_obj = target_version && Dependabot::Julia::Version.new(target_version)

        requirements.map do |requirement|
          floor = stdlib_versions.fetch(requirement.file.to_s, [])
          next update_stdlib_requirement(requirement, floor) if floor.any?
          next requirement unless target_version_obj

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

      sig { returns(T::Hash[String, T::Array[String]]) }
      attr_reader :stdlib_versions

      # A stdlib's compat entry has to admit every version the project can
      # meet across its Julia range rather than track the registry's latest
      # release, so it is only ever widened to cover the missing ones,
      # whatever strategy is configured.
      sig do
        params(
          requirement: Dependabot::DependencyRequirement,
          floor: T::Array[String]
        ).returns(Dependabot::DependencyRequirement)
      end
      def update_stdlib_requirement(requirement, floor)
        current_requirement = requirement.requirement_string
        # Explicit ranges are manual constraints, as in updated_version_requirement
        return requirement if current_requirement&.match?(Dependabot::Julia::Requirement::HYPHEN_RANGE_PATTERN)

        versions = floor.map { |version| Dependabot::Julia::Version.new(version) }
        new_requirement = if current_requirement.nil?
                            versions.map { |version| stdlib_version_spec(version) }.join(", ")
                          else
                            widened_stdlib_requirement(current_requirement, versions)
                          end
        return requirement if new_requirement == current_requirement

        Dependabot::DependencyRequirement.create(requirement.merge(requirement: new_requirement))
      end

      sig { params(requirement_string: String, versions: T::Array[Dependabot::Julia::Version]).returns(String) }
      def widened_stdlib_requirement(requirement_string, versions)
        reqs = Dependabot::Julia::Requirement.requirements_array(requirement_string)
        missing = versions.reject { |version| reqs.any? { |req| req.satisfied_by?(version) } }

        missing.reduce(requirement_string) do |entry, version|
          append_spec_string(entry, stdlib_version_spec(version))
        end
      end

      # Same shape as simplified_version_spec, except that "1.0.0" reads as
      # "1" (the stdlib line, not a particular release) and 0.0.0 stands for
      # the old test sandbox pin, written as the PSA recommends
      sig { params(version: Dependabot::Julia::Version).returns(String) }
      def stdlib_version_spec(version)
        major = (version.segments[0] || 0).to_i
        minor = (version.segments[1] || 0).to_i
        patch = (version.segments[2] || 0).to_i

        return "< 0.0.1" if major.zero? && minor.zero? && patch.zero?
        return major.to_s if major.positive? && minor.zero?

        simplified_version_spec(version)
      end

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
                            target_version.to_s
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
        append_spec_string(requirement_string, simplified_version_spec(target_version))
      end

      sig { params(requirement_string: String, new_spec: String).returns(String) }
      def append_spec_string(requirement_string, new_spec)
        # Append the new spec to the existing requirement (CompatHelper KeepEntry behavior)
        # Detect whether the existing requirement uses spaces after commas and preserve that format
        # and default to ", " if no commas found
        separator = requirement_string.include?(",") && !requirement_string.include?(", ") ? "," : ", "
        "#{requirement_string}#{separator}#{new_spec}"
      end

      sig { params(target_version: Dependabot::Julia::Version).returns(String) }
      def simplified_version_spec(target_version)
        # Follow CompatHelper.jl's compat_version_number logic:
        # - major > 0: use "major.minor"
        # - major == 0, minor > 0: use "0.minor"
        # - major == 0, minor == 0: use "0.0.patch"
        # Note: CompatHelper always returns plain versions (no ^ or ~ prefix)
        # Coerce segments to integers (segments may be Integer or String or nil)
        major = (target_version.segments[0] || 0).to_i
        minor = (target_version.segments[1] || 0).to_i
        patch = (target_version.segments[2] || 0).to_i

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
