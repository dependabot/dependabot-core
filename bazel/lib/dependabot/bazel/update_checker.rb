# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/bazel/version"
require "dependabot/bazel/update_checker/bzlmod_version_finder"
require "dependabot/bazel/update_checker/workspace_version_finder"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          ignored_versions: T::Array[String],
          raise_on_ignored: T::Boolean,
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          requirements_update_strategy: T.nilable(Dependabot::RequirementsUpdateStrategy),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          update_cooldown: T.untyped, # TODO: Define proper cooldown type
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        dependency:,
        dependency_files:,
        credentials:,
        repo_contents_path: nil,
        ignored_versions: [],
        raise_on_ignored: false,
        security_advisories: [],
        requirements_update_strategy: nil,
        dependency_group: nil,
        update_cooldown: nil,
        options: {}
      )
        @latest_version = T.let(nil, T.nilable(T.any(String, Gem::Version)))
        @latest_resolvable_version = T.let(nil, T.nilable(T.any(String, Gem::Version)))
        @updated_requirements = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))

        super
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        return unless latest_version

        @latest_resolvable_version ||= fetch_latest_resolvable_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        @updated_requirements ||= fetch_updated_requirements
      end

      sig { override.returns(T::Boolean) }
      def up_to_date?
        # Check if we already have the latest version
        return true if latest_version.nil?
        return true if dependency.version == latest_version.to_s

        # Check for security updates
        if security_advisories.any? && dependency.version
          current_version_obj = version_class.new(dependency.version) if version_class.correct?(dependency.version)
          return false if current_version_obj && vulnerable_versions.include?(current_version_obj)
        end

        super
      end

      sig { returns(T::Boolean) }
      def vulnerable?
        return false unless dependency.version
        return false unless version_class.correct?(dependency.version)

        current_version_obj = version_class.new(dependency.version)
        vulnerable_versions.include?(current_version_obj)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        return nil unless vulnerable?
        return nil unless latest_version

        # For now, return the latest version as the security fix
        # TODO: Implement proper security advisory checking
        version_class.new(latest_version.to_s) if version_class.correct?(latest_version.to_s)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        return nil unless vulnerable?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version_with_no_unlock
        # For now, return the latest version if it doesn't require unlocking constraints
        # TODO: Implement proper constraint checking
        latest_resolvable_version
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # For now, assume latest version is always resolvable with full unlock
        # TODO: Implement proper dependency resolution
        !latest_version.nil?
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        # TODO: Return updated dependencies if full unlock is needed
        []
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_version
        # Use the appropriate version finder based on dependency source
        version_finder = create_version_finder
        return nil unless version_finder

        version_finder.latest_version
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_resolvable_version
        # For now, assume latest version is resolvable
        # TODO: Implement proper dependency resolution
        latest_version
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def fetch_updated_requirements
        # Use the appropriate version finder to get updated requirements
        version_finder = create_version_finder
        return dependency.requirements unless version_finder

        version_finder.updated_requirements
      end

      sig { returns(T.nilable(T.any(BzlmodVersionFinder, WorkspaceVersionFinder))) }
      def create_version_finder
        if bzlmod_dependency?
          BzlmodVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions
          )
        elsif workspace_dependency?
          WorkspaceVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          )
        else
          # Dependency referenced in BUILD files but not defined in MODULE.bazel/WORKSPACE
          nil
        end
      end

      sig { returns(T::Boolean) }
      def bzlmod_dependency?
        # Check if dependency is defined in MODULE.bazel files
        module_files.any? do |file|
          content = file.content
          next false unless content

          content.include?("bazel_dep(name = \"#{dependency.name}\"")
        end
      end

      sig { returns(T::Boolean) }
      def workspace_dependency?
        # Check if dependency is defined in WORKSPACE files
        workspace_files.any? do |file|
          content = file.content
          next false unless content

          content.include?("name = \"#{dependency.name}\"") &&
            (content.include?("http_archive") || content.include?("git_repository"))
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def module_files
        @module_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?("MODULE.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def workspace_files
        @workspace_files ||= T.let(
          dependency_files.select { |f| f.name == "WORKSPACE" || f.name.end_with?("WORKSPACE.bazel") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::Version]) }
      def vulnerable_versions
        @vulnerable_versions ||= T.let(
          begin
            return [] unless dependency.version
            return [] unless version_class.correct?(dependency.version)

            current_version = version_class.new(dependency.version)
            security_advisories.select { |advisory| advisory.vulnerable?(current_version) }
                              .map { |_advisory| current_version }
          end,
          T.nilable(T::Array[Dependabot::Version])
        )
      end

      sig { returns(T.class_of(Dependabot::Version)) }
      def version_class
        Dependabot::Bazel::Version
      end
    end
  end
end

Dependabot::UpdateCheckers.register("bazel", Dependabot::Bazel::UpdateChecker)
