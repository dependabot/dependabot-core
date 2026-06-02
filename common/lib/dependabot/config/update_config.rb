# typed: strict
# frozen_string_literal: true

require "dependabot/config/allow_condition"
require "dependabot/config/ignore_condition"
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

      sig { returns(T::Array[AllowCondition]) }
      attr_reader :allow_conditions

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :exclude_paths

      sig do
        params(
          ignore_conditions: T.nilable(T::Array[IgnoreCondition]),
          allow_conditions: T.nilable(T::Array[AllowCondition]),
          commit_message_options: T.nilable(CommitMessageOptions),
          exclude_paths: T.nilable(T::Array[String])
        ).void
      end
      def initialize(ignore_conditions: nil, allow_conditions: nil, commit_message_options: nil, exclude_paths: nil)
        @ignore_conditions = T.let(ignore_conditions || [], T::Array[IgnoreCondition])
        @allow_conditions = T.let(allow_conditions || [], T::Array[AllowCondition])
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

        @ignore_conditions
          .select { |ic| self.class.wildcard_match?(T.must(normalizer).call(ic.dependency_name), dep_name) }
          .map { |ic| ic.ignored_versions(dependency, security_updates_only) }
          .flatten
          .compact
          .uniq
      end

      sig { params(dependency: Dependency, security_updates_only: T::Boolean).returns(T::Array[String]) }
      def allowed_versions_for(dependency, security_updates_only: false)
        normalizer = name_normaliser_for(dependency)
        dep_name = T.must(normalizer).call(dependency.name)

        @allow_conditions
          .select { |ac| self.class.wildcard_match?(T.must(normalizer).call(ac.dependency_name), dep_name) }
          .select { |ac| dependency_type_matches?(ac.dependency_type, dependency) }
          .flat_map { |ac| ac.allowed_versions(dependency, security_updates_only: security_updates_only) }
          .compact
          .uniq
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

      TOP_LEVEL_DEPENDENCY_TYPES = T.let(%w(direct production development).freeze, T::Array[String])

      private

      sig { params(dep_type: T.nilable(String), dependency: Dependency).returns(T::Boolean) }
      def dependency_type_matches?(dep_type, dependency)
        return true if dep_type.nil? || dep_type == "all"

        # Indirect deps don't match top-level-typed rules
        return false if dependency.requirements.none? && TOP_LEVEL_DEPENDENCY_TYPES.include?(dep_type)

        case dep_type
        when "production" then dependency.production?
        when "development" then !dependency.production?
        when "direct" then dependency.requirements.any?
        when "indirect" then dependency.requirements.none?
        else true
        end
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
