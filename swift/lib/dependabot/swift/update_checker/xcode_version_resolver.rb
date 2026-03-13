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
          return nil unless version_pinned?

          tag = git_commit_checker.local_tag_for_latest_version
          return nil unless tag

          version = tag.fetch(:version)
          return nil unless version_meets_requirements?(version)

          Version.new(version)
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

        sig { returns(T.nilable(Dependabot::Swift::Requirement)) }
        def dependency_requirement
          req_string = dependency.requirements.first&.dig(:requirement)
          return nil unless req_string

          Dependabot::Swift::Requirement.new(req_string)
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
