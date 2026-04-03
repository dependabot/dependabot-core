# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/git_commit_checker"
require "dependabot/swift/update_checker"
require "dependabot/swift/requirement"
require "dependabot/swift/version"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      # Resolves versions for Xcode-only SwiftPM projects (no Package.swift).
      #
      # Unlike the classic VersionResolver which relies on `swift package update`,
      # this resolver uses GitCommitChecker to find the latest available version
      # from git tags, since we cannot run the Swift CLI without a manifest.
      class XcodeVersionResolver
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            git_commit_checker: Dependabot::GitCommitChecker,
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def initialize(dependency:, git_commit_checker:, security_advisories:)
          @dependency = dependency
          @git_commit_checker = git_commit_checker
          @security_advisories = security_advisories
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version
          tag = latest_resolvable_version_tag
          return nil unless tag

          Version.new(tag.fetch(:version))
        end

        # Returns the full tag info including commit_sha for the latest resolvable version
        # Memoized to avoid redundant computation when called from UpdateChecker
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_resolvable_version_tag
          @latest_resolvable_version_tag ||= T.let(
            compute_latest_resolvable_version_tag,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_security_fix_version
          return nil unless version_pinned?

          tags = git_commit_checker.local_tags_for_allowed_versions
          relevant_tags = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
            tags,
            security_advisories
          )
          relevant_tags = filter_lower_tags(relevant_tags)

          lowest_tag = relevant_tags.min_by { |tag| tag.fetch(:version) }
          return nil unless lowest_tag

          Version.new(lowest_tag.fetch(:version))
        end

        sig { returns(T::Boolean) }
        def version_pinned?
          return false unless dependency.version

          Version.correct?(dependency.version)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def compute_latest_resolvable_version_tag
          return nil unless version_pinned?

          # For versionRange, we need to find the highest version within the range,
          # not just check if the absolute latest satisfies it
          return compute_latest_version_in_range if requirement_kind == "versionRange"

          tag = git_commit_checker.local_tag_for_latest_version
          return nil unless tag

          version = tag.fetch(:version)
          return nil unless version_meets_requirements?(version)

          tag
        end

        # For versionRange requirements, find the highest version that satisfies
        # the explicit upper bound constraint. We don't filter out lower versions here
        # because `can_update?` will decide whether an update is actually needed.
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def compute_latest_version_in_range
          requirement = dependency_requirement
          return nil unless requirement

          tags = git_commit_checker.local_tags_for_allowed_versions
          matching_tags = tags.select { |tag| requirement.satisfied_by?(tag.fetch(:version)) }

          matching_tags.max_by { |tag| tag.fetch(:version) }
        end

        sig { returns(T.nilable(Dependabot::Swift::Requirement)) }
        def dependency_requirement
          req_string = dependency.requirements.first&.dig(:requirement)
          return nil unless req_string

          Dependabot::Swift::Requirement.new(req_string)
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig { returns(T.nilable(String)) }
        def requirement_kind
          dependency.requirements.first&.dig(:metadata, :kind)
        end

        sig { params(version: T.untyped).returns(T::Boolean) }
        def version_meets_requirements?(version)
          kind = requirement_kind

          # For most Xcode requirement kinds, we update the requirement itself to match
          # the new version, so we don't need to check if the new version satisfies
          # the current requirement:
          # - exactVersion: requirement changes to exact new version
          # - upToNextMajorVersion: requirement updates to new version's major range
          # - upToNextMinorVersion: requirement updates to new version's minor range
          #
          # Only versionRange has an explicit upper bound that should be respected.
          return true if %w(exactVersion upToNextMajorVersion upToNextMinorVersion).include?(kind)

          # For sub-dependencies that are not declared directly in project.pbxproj
          # (e.g., transitive dependencies of local packages), kind will be nil and
          # the requirement comes from Package.resolved as an equality pin.
          # In this case, we allow updates since the actual constraint lives in
          # the local package's Package.swift, which we don't have access to.
          # This may produce a pin that is not resolvable for the full package graph.
          # In Xcode mode we intentionally defer that validation to downstream
          # SwiftPM/Xcode resolution.
          return true if kind.nil? && package_resolved_requirement?

          requirement = dependency_requirement
          return true unless requirement

          requirement.satisfied_by?(version)
        end

        # Returns true if the dependency's requirement originates from a
        # Package.resolved file (rather than project.pbxproj).
        sig { returns(T::Boolean) }
        def package_resolved_requirement?
          dependency.requirements.any? do |req|
            file = req[:file]
            file.is_a?(String) && file.end_with?("Package.resolved")
          end
        end

        sig do
          params(
            tags: T::Array[T::Hash[Symbol, T.untyped]]
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def filter_lower_tags(tags)
          current = current_version
          return tags unless current

          tags.select { |tag| tag.fetch(:version) > current }
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_version
          return nil unless dependency.version

          Version.new(dependency.version)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
