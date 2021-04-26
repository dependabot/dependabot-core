# frozen_string_literal: true

require "dependabot/config/ignore_condition"

module Dependabot
  module Config
    # Configuration for a single ecosystem
    class UpdateConfig
      attr_reader :commit_message_options, :ignore_conditions
      def initialize(ignore_conditions: nil, commit_message_options: nil)
        @ignore_conditions = ignore_conditions || []
        @commit_message_options = commit_message_options
      end

      def ignored_versions_for(dependency, security_updates_only: false)
        normalizer = name_normaliser_for(dependency)
        dep_name = name_normaliser_for(dependency).call(dependency.name)

        @ignore_conditions.
          select { |ic| self.class.wildcard_match?(normalizer.call(ic.dependency_name), dep_name) }.
          map { |ic| ic.ignored_versions(dependency, security_updates_only) }.
          flatten.
          compact.
          uniq
      end

      def ignored_update?(updated_dependency, security_updates_only: false)
        # NOTE: Build a dependency and ignore condition with the previous_version
        # that will ignore the updated dependency version
        version_class = version_class_for(updated_dependency)
        updated_version = updated_dependency.version
        if version_class.correct?(updated_dependency.version)
          updated_version = version_class.new(updated_dependency.version)
        end
        previous_dependency = build_previous_dependency(updated_dependency)
        ignored_versions_for(previous_dependency, security_updates_only: security_updates_only).
          flat_map { |version| requirement_class_for(previous_dependency).requirements_array(version) }.
          any? { |req| req.satisfied_by?(updated_version) }
      end

      def self.wildcard_match?(wildcard_string, candidate_string)
        return false unless wildcard_string && candidate_string

        regex_string = "a#{wildcard_string.downcase}a".split("*").
                       map { |p| Regexp.quote(p) }.
                       join(".*").gsub(/^a|a$/, "")
        regex = /^#{regex_string}$/
        regex.match?(candidate_string.downcase)
      end

      private

      def requirement_class_for(dependency)
        Utils.version_class_for_package_manager(dependency.package_manager)
      end

      def version_class_for(dependency)
        Utils.version_class_for_package_manager(dependency.package_manager)
      end

      def build_previous_dependency(previous_dependency)
        Dependabot::Dependency.new(
          name: previous_dependency.name,
          version: previous_dependency.previous_version,
          requirements: previous_dependency.previous_requirements || [],
          package_manager: previous_dependency.package_manager
        )
      end

      def name_normaliser_for(dep)
        name_normaliser ||= {}
        name_normaliser[dep] ||= Dependency.name_normaliser_for_package_manager(dep.package_manager)
      end

      class CommitMessageOptions
        attr_reader :prefix, :prefix_development, :include

        def initialize(prefix:, prefix_development:, include:)
          @prefix = prefix
          @prefix_development = prefix_development
          @include = include
        end

        def include_scope?
          @include == "scope"
        end

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
