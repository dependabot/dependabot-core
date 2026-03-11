# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/git_commit_checker"
require "dependabot/swift/update_checker"
require "dependabot/swift/version"

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
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def initialize(dependency:, credentials:, ignored_versions:, raise_on_ignored:, security_advisories:)
          @dependency = dependency
          @credentials = credentials
          @ignored_versions = ignored_versions
          @raise_on_ignored = raise_on_ignored
          @security_advisories = security_advisories
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version
          return nil unless version_pinned?

          tag = git_commit_checker.local_tag_for_latest_version
          return nil unless tag

          version = tag.fetch(:version)
          return nil unless version_meets_requirements?(version)

          Version.new(version)
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version_within_requirements
          return nil unless version_pinned?

          requirement = dependency_requirement
          return nil unless requirement

          tags = git_commit_checker.local_tags_for_allowed_versions
          matching_tags = tags.select do |tag|
            version = tag.fetch(:version)
            requirement.satisfied_by?(version)
          end

          latest_tag = matching_tags.max_by { |tag| tag.fetch(:version) }
          return nil unless latest_tag

          Version.new(latest_tag.fetch(:version))
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_security_fix_version
          return nil unless version_pinned?

          tags = git_commit_checker.local_tags_for_allowed_versions
          relevant_tags = filter_vulnerable_versions(tags)
          relevant_tags = filter_lower_tags(relevant_tags)

          lowest_tag = relevant_tags.min_by { |tag| tag.fetch(:version) }
          return nil unless lowest_tag

          Version.new(lowest_tag.fetch(:version))
        end

        sig { returns(T::Boolean) }
        def branch_has_updates?
          return false unless branch_pinned?

          branch = dependency_branch
          return false unless branch

          begin
            git_commit_checker.branch_or_ref_in_release?(branch)
          rescue StandardError
            false
          end
        end

        sig { returns(T::Boolean) }
        def version_pinned?
          return false unless dependency.version

          Version.correct?(dependency.version)
        end

        sig { returns(T::Boolean) }
        def branch_pinned?
          source = dependency.requirements.first&.dig(:source)
          return false unless source

          source[:branch].is_a?(String) && !source[:branch].empty?
        end

        sig { returns(T::Boolean) }
        def revision_pinned?
          return true unless dependency.version
          return false if version_pinned?

          # Has a revision but no version
          source = dependency.requirements.first&.dig(:source)
          source&.dig(:ref).is_a?(String)
        end

        sig { returns(T.nilable(String)) }
        def dependency_branch
          source = dependency.requirements.first&.dig(:source)
          source&.dig(:branch)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

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

        sig { returns(T.nilable(Dependabot::Requirement)) }
        def dependency_requirement
          req_string = dependency.requirements.first&.dig(:requirement)
          return nil unless req_string

          Requirement.new(req_string)
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig { params(version: T.untyped).returns(T::Boolean) }
        def version_meets_requirements?(version)
          requirement = dependency_requirement
          return true unless requirement

          requirement.satisfied_by?(version)
        end

        sig do
          params(
            tags: T::Array[T::Hash[Symbol, T.untyped]]
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def filter_vulnerable_versions(tags)
          return tags if security_advisories.empty?

          tags.reject do |tag|
            version = tag.fetch(:version)
            security_advisories.any? { |advisory| advisory.vulnerable?(version) }
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
