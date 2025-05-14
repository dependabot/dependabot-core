# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "dependabot/git_commit_checker"
require "dependabot/swift/native_requirement"
require "dependabot/swift/file_updater/manifest_updater"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        @latest_version ||= T.let(fetch_latest_version, T.nilable(Dependabot::Version))
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        Dependabot.logger.info("Running node command: latest_resolvable_version")
        @latest_resolvable_version = T.let(fetch_latest_resolvable_version, T.nilable(Dependabot::Version))
      end

      sig { override.returns(T.noreturn) }
      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        @lowest_security_fix_version ||= T.let(fetch_lowest_security_fix_version, T.nilable(Dependabot::Version))
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        @lowest_resolvable_security_fix_version = T.let(
          fetch_lowest_resolvable_security_fix_version,
          T.nilable(Dependabot::Version)
        )
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: old_requirements,
          target_version: T.must(preferred_resolvable_version)
        ).updated_requirements
      end

      private

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def old_requirements
        dependency.requirements
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_latest_version
        return unless git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag

        tag = latest_version_tag
        return unless tag

        tag.fetch(:version)
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_lowest_security_fix_version
        return unless git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag

        tag = lowest_security_fix_version_tag
        return unless tag

        tag.fetch(:version)
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_latest_resolvable_version

        latest_resolvable_version = version_resolver_for(unlocked_requirements).latest_resolvable_version
        return current_version unless latest_resolvable_version

        Version.new(latest_resolvable_version)
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_lowest_resolvable_security_fix_version
        lowest_resolvable_security_fix_version = version_resolver_for(
          force_lowest_security_fix_requirements
        ).latest_resolvable_version
        return unless lowest_resolvable_security_fix_version

        Version.new(lowest_resolvable_security_fix_version)
      end

      sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(VersionResolver) }
      def version_resolver_for(requirements)
        VersionResolver.new(
          dependency: dependency,
          manifest: prepare_manifest_for(requirements),
          lockfile: lockfile,
          repo_contents_path: repo_contents_path,
          credentials: credentials
        )
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def unlocked_requirements
        NativeRequirement.map_requirements(old_requirements) do |_old_requirement|
          "\"#{dependency.version}\"...\"#{latest_version}\""
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def force_lowest_security_fix_requirements
        NativeRequirement.map_requirements(old_requirements) do |_old_requirement|
          "\"#{lowest_security_fix_version}\"...\"#{lowest_security_fix_version}\""
        end
      end

      sig { params(new_requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(Dependabot::DependencyFile) }
      def prepare_manifest_for(new_requirements)
        manifest_file = T.must(manifest)

        DependencyFile.new(
          name: manifest_file.name,
          content: FileUpdater::ManifestUpdater.new(
            T.must(manifest_file.content),
            old_requirements: old_requirements,
            new_requirements: new_requirements
          ).updated_manifest_content,
          directory: manifest_file.directory
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest
        @manifest ||= T.let(
          dependency_files.find { |file| file.name == "Package.swift" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          dependency_files.find { |file| file.name == "Package.resolved" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Swift (yet)
        false
      end

      sig { override.returns(T.noreturn) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            consider_version_branches_pinned: true
          ),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def latest_version_tag
        git_commit_checker.local_tag_for_latest_version
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def lowest_security_fix_version_tag
        tags = git_commit_checker.local_tags_for_allowed_versions
        find_lowest_secure_version(tags)
      end

      sig { params(tags: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def find_lowest_secure_version(tags)
        relevant_tags = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(tags, security_advisories)
        relevant_tags = filter_lower_tags(relevant_tags)

        relevant_tags.min_by { |tag| tag.fetch(:version) }
      end

      sig { params(tags_array: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def filter_lower_tags(tags_array)
        return tags_array unless current_version

        tags_array
          .select { |tag| tag.fetch(:version) > current_version }
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("swift", Dependabot::Swift::UpdateChecker)
