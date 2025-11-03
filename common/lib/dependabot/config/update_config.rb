# typed: strict
# frozen_string_literal: true

require "dependabot/config/ignore_condition"
require "dependabot/utils"
require "sorbet-runtime"

module Dependabot
  module Config
    # Configuration for a single ecosystem
    class UpdateConfig
      extend T::Sig

      sig { returns(T.nilable(CommitMessageOptions)) }
      attr_reader :commit_message_options

      sig { returns(T::Array[IgnoreCondition]) }
      attr_reader :ignore_conditions

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :exclude_paths

      sig do
        params(
          ignore_conditions: T.nilable(T::Array[IgnoreCondition]),
          commit_message_options: T.nilable(CommitMessageOptions),
          exclude_paths: T.nilable(T::Array[String])
        ).void
      end
      def initialize(ignore_conditions: nil, commit_message_options: nil, exclude_paths: nil)
        @ignore_conditions = T.let(ignore_conditions || [], T::Array[IgnoreCondition])
        @commit_message_options = commit_message_options
        @exclude_paths = exclude_paths
      end

      sig { params(dependency: Dependency, security_updates_only: T::Boolean).returns(T::Array[String]) }
      def ignored_versions_for(dependency, security_updates_only: false)
        normalizer = name_normaliser_for(dependency)
        dep_name = T.must(normalizer).call(dependency.name)

        if dependency.version.nil? && dependency.requirements.any?
          dependency = extract_base_version_from_requirement(dependency)
        end

        ignored = @ignore_conditions
                  .select { |ic| self.class.wildcard_match?(T.must(normalizer).call(ic.dependency_name), dep_name) }
                  .map { |ic| ic.ignored_versions(dependency, security_updates_only) }
                  .flatten
                  .compact
                  .uniq

        # Filter out ignore conditions that don't overlap with any of the dependency's requirements
        # This prevents ignore conditions created in one requirement context from blocking updates
        # in other requirement contexts with different constraints
        filter_non_overlapping_ignores(ignored, dependency)
      end

      sig { params(dependency: Dependency).returns(Dependency) }
      def extract_base_version_from_requirement(dependency)
        requirements = dependency.requirements
        requirement = T.must(requirements.first)[:requirement]
        version = requirement&.match(/\d+\.\d+\.\d+/)&.to_s
        Dependabot::Dependency.new(
          name: dependency.name,
          version: version,
          requirements: dependency.requirements,
          package_manager: dependency.package_manager
        )
      end

      sig { params(wildcard_string: T.nilable(String), candidate_string: T.nilable(String)).returns(T::Boolean) }
      def self.wildcard_match?(wildcard_string, candidate_string)
        return false unless wildcard_string && candidate_string

        regex_string = "a#{wildcard_string.downcase}a".split("*")
                                                      .map { |p| Regexp.quote(p) }
                                                      .join(".*").gsub(/^a|a$/, "")
        regex = /^#{regex_string}$/
        regex.match?(candidate_string.downcase)
      end

      private

      # Filters out ignore conditions that have no overlap with the dependency's requirements.
      # For example, if a requirement is "< 2.0" and an ignore is ">= 2.0", the ignore doesn't
      # affect this requirement and should be filtered out.
      sig { params(ignored_versions: T::Array[String], dependency: Dependency).returns(T::Array[String]) }
      def filter_non_overlapping_ignores(ignored_versions, dependency)
        return ignored_versions if dependency.requirements.empty?

        requirement_class = begin
          Utils.requirement_class_for_package_manager(dependency.package_manager)
        rescue StandardError
          # If package manager is not registered, return all ignores to be safe
          return ignored_versions
        end

        # Parse dependency requirements
        dep_requirements = dependency.requirements.flat_map do |req|
          req_string = req[:requirement]
          next [] if req_string.nil? || req_string.empty?

          begin
            requirement_class.requirements_array(req_string)
          rescue StandardError
            []
          end
        end

        return ignored_versions if dep_requirements.empty?

        # Filter ignored versions that overlap with at least one requirement
        ignored_versions.select do |ignored_version|
          ignore_overlaps_with_requirements?(ignored_version, dep_requirements, requirement_class)
        rescue StandardError => e
          # If we can't parse/compare, keep the ignore to be safe
          Dependabot.logger.debug("Error filtering ignore '#{ignored_version}': #{e.message}")
          true
        end
      end

      # Checks if an ignore condition overlaps with any of the dependency's requirements
      sig do
        params(
          ignored_version: String,
          dep_requirements: T::Array[Gem::Requirement],
          requirement_class: T.class_of(Gem::Requirement)
        ).returns(T::Boolean)
      end
      def ignore_overlaps_with_requirements?(ignored_version, dep_requirements, requirement_class)
        begin
          ignore_reqs = requirement_class.requirements_array(ignored_version)
        rescue StandardError
          # If we can't parse the ignore, keep it to be safe
          return true
        end

        # Check if there's any overlap between ignore requirements and dependency requirements
        # An overlap exists if there's at least one version that satisfies both
        dep_requirements.any? do |dep_req|
          ignore_reqs.any? { |ignore_req| requirements_overlap?(dep_req, ignore_req) }
        end
      end

      # Checks if two requirements have any overlapping versions
      # This is a conservative check - returns true unless we can prove they don't overlap
      sig { params(req1: Gem::Requirement, req2: Gem::Requirement).returns(T::Boolean) }
      def requirements_overlap?(req1, req2)
        req1_specs = req1.requirements
        req2_specs = req2.requirements

        # Check if requirements are disjoint (don't overlap)
        # This handles common cases like "< 2.0" and ">= 2.0"
        req1_specs.each do |op1, ver1|
          req2_specs.each do |op2, ver2|
            return false if disjoint_requirements?(op1, ver1, op2, ver2)
          end
        end

        # If we can't prove they don't overlap, assume they do
        true
      rescue StandardError
        # If comparison fails, assume overlap to be safe
        true
      end

      # Checks if two requirement specifications are disjoint (have no overlapping versions)
      # Note: This only handles upper/lower bound disjoint cases (e.g., "< 2.0" and ">= 2.0").
      # Other disjoint cases like conflicting exact versions (e.g., "= 1.0" and "= 2.0") are not
      # detected and will conservatively be treated as overlapping.
      sig do
        params(
          op1: String,
          ver1: Gem::Version,
          op2: String,
          ver2: Gem::Version
        ).returns(T::Boolean)
      end
      def disjoint_requirements?(op1, ver1, op2, ver2)
        # Check if req1 has upper bound and req2 has lower bound
        return disjoint_upper_lower?(op1, ver1, op2, ver2) if upper_bound?(op1) && lower_bound?(op2)

        # Check if req2 has upper bound and req1 has lower bound
        return disjoint_upper_lower?(op2, ver2, op1, ver1) if upper_bound?(op2) && lower_bound?(op1)

        false
      end

      # Checks if an operator represents an upper bound
      sig { params(operator: String).returns(T::Boolean) }
      def upper_bound?(operator)
        operator == "<" || operator == "<="
      end

      # Checks if an operator represents a lower bound
      sig { params(operator: String).returns(T::Boolean) }
      def lower_bound?(operator)
        operator == ">" || operator == ">="
      end

      # Checks if upper and lower bound requirements are disjoint
      sig do
        params(
          upper_op: String,
          upper_ver: Gem::Version,
          lower_op: String,
          lower_ver: Gem::Version
        ).returns(T::Boolean)
      end
      def disjoint_upper_lower?(upper_op, upper_ver, lower_op, lower_ver)
        # "< X" and ">= Y" are disjoint if Y >= X
        return lower_ver >= upper_ver if upper_op == "<" && lower_op == ">="

        # "< X" and "> Y" are disjoint if Y >= X
        return lower_ver >= upper_ver if upper_op == "<" && lower_op == ">"

        # "<= X" and ">= Y" are disjoint if Y > X
        return lower_ver > upper_ver if upper_op == "<=" && lower_op == ">="

        # "<= X" and "> Y" are disjoint if Y >= X
        return lower_ver >= upper_ver if upper_op == "<=" && lower_op == ">"

        false
      end

      sig { params(dep: Dependency).returns(T.nilable(T.proc.params(arg0: String).returns(String))) }
      def name_normaliser_for(dep)
        name_normaliser ||= {}
        name_normaliser[dep] ||= Dependency.name_normaliser_for_package_manager(dep.package_manager)
      end

      class CommitMessageOptions
        extend T::Sig

        sig { returns(T.nilable(String)) }
        attr_reader :prefix

        sig { returns(T.nilable(String)) }
        attr_reader :prefix_development

        sig { returns(T.nilable(String)) }
        attr_reader :include

        sig do
          params(
            prefix: T.nilable(String),
            prefix_development: T.nilable(String),
            include: T.nilable(String)
          )
            .void
        end
        def initialize(prefix:, prefix_development:, include:)
          @prefix = prefix
          @prefix_development = prefix_development
          @include = include
        end

        sig { returns(T::Boolean) }
        def include_scope?
          @include == "scope"
        end

        sig { returns(T::Hash[Symbol, String]) }
        def to_h
          {
            prefix: @prefix,
            prefix_development: @prefix_development,
            include_scope: include_scope?
          }
        end
      end
    end
  end
end
