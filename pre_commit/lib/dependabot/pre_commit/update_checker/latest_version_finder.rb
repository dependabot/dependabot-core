# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pre_commit/comment_version_helper"
require "dependabot/pre_commit/file_parser"
require "dependabot/pre_commit/package/package_details_fetcher"
require "dependabot/pre_commit/requirement"
require "dependabot/pre_commit/update_checker"
require "dependabot/pre_commit/helpers"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module PreCommit
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
            options: T::Hash[Symbol, T.untyped],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          raise_on_ignored:,
          options: {},
          cooldown_options: nil
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @options             = options
          @cooldown_options = cooldown_options

          @git_helper = T.let(git_helper, Dependabot::PreCommit::Helpers::Githelper)
          super(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: [],
            cooldown_options: cooldown_options,
            raise_on_ignored: raise_on_ignored,
            options: options
          )
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def latest_release_version
          release = available_release
          return nil unless release

          Dependabot.logger.info("Available release version/ref is #{release}")

          # Commit SHA releases have no version ordering to apply cooldown against.
          return release if release_type_sha?
          return release unless cooldown_active?

          selected = cooldown_selected_tag
          return T.cast(selected.fetch(:version), Dependabot::Version) if selected

          # No newer version is available outside its cooldown window — either
          # every candidate is still cooling down, or the only remaining tags
          # aren't newer than the current pin — so keep the current version.
          Dependabot.logger.info("No newer version outside cooldown; keeping #{current_version}")
          current_version
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          return available_latest_version_tag unless cooldown_active? && !release_type_sha?

          cooldown_selected_tag
        end

        private

        # Resolves the newest version tag outside its cooldown window by
        # delegating to the shared GitCommitChecker cooldown (which handles
        # release-date resolution and is semver-aware). Version-pinned deps keep
        # their existing tag precision; a SHA pinned with a version comment has
        # no precision to match against, so all allowed tags are considered.
        # Tags that aren't newer than the current pinned version are ignored, so
        # cooldown never proposes moving backwards.
        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def cooldown_selected_tag
          return @cooldown_selected_tag if defined?(@cooldown_selected_tag)

          checker = @git_helper.git_commit_checker
          tag = if sha_pinned_with_version_comment?
                  checker.local_tag_for_latest_version(cooldown_options)
                else
                  checker.local_tag_for_latest_version_matching_existing_precision(cooldown_options)
                end

          @cooldown_selected_tag = T.let(
            tag && newer_than_current?(tag) ? tag : nil,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        # The shared cooldown returns the highest allowed tag left after
        # filtering; guard against it being the current version (or older) so a
        # cooled-down latest never falls back to a same-or-older tag.
        sig { params(tag: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def newer_than_current?(tag)
          cur = current_version
          return true unless cur.is_a?(Dependabot::Version)

          tag_version = tag[:version]
          return false unless tag_version.is_a?(Gem::Version)

          comparison = tag_version <=> cur
          !comparison.nil? && comparison.positive?
        end

        sig { returns(T::Boolean) }
        def cooldown_active?
          cooldown_enabled? && !cooldown_options.nil?
        end

        sig { returns(T.nilable(Dependabot::PreCommit::Package::PackageDetailsFetcher)) }
        def package_details_fetcher
          @package_details_fetcher ||= T.let(
            Dependabot::PreCommit::Package::PackageDetailsFetcher
                        .new(
                          dependency: dependency,
                          credentials: credentials,
                          ignored_versions: ignored_versions,
                          raise_on_ignored: raise_on_ignored
                        ),
            T.nilable(Dependabot::PreCommit::Package::PackageDetailsFetcher)
          )
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def available_release
          @available_release = T.let(
            T.must(package_details_fetcher).release_list_for_git_dependency,
            T.nilable(T.any(Dependabot::Version, String))
          )
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def available_latest_version_tag
          @latest_version_tag = T.let(
            T.must(package_details_fetcher).latest_version_tag,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def current_version
          return dependency.source_details(allowed_types: ["git"])&.fetch(:ref) if release_type_sha?

          # numeric_version handles plain versions like "4.4.0"
          numeric = dependency.numeric_version
          return numeric if numeric

          # Handle v-prefixed tags like "v4.4.0" common in pre-commit
          version_str = dependency.version
          return nil unless version_str

          stripped = version_str.sub(/\Av/i, "")
          return version_from_frozen_comment unless Dependabot::PreCommit::Version.correct?(stripped)

          Dependabot::PreCommit::Version.new(stripped)
        end

        sig { returns(T::Boolean) }
        def release_type_sha?
          available_release.is_a?(String)
        end

        # Returns true when the dependency's stored ref isn't a semantic version (e.g., a commit SHA)
        # but a frozen version comment (e.g. "# frozen: v5.0.0") provides a semantic
        # version we can use for version ordering and tag selection.
        sig { returns(T::Boolean) }
        def sha_pinned_with_version_comment?
          return false if release_type_sha?

          version_str = dependency.version
          return false unless version_str

          !Dependabot::PreCommit::Version.correct?(version_str) && !version_from_frozen_comment.nil?
        end

        # Extracts the semantic version from a frozen comment (e.g. "# frozen: v5.0.0")
        # when the dependency's stored version is a commit SHA.
        sig { returns(T.nilable(Dependabot::Version)) }
        def version_from_frozen_comment
          comment = dependency.requirements.first&.dig(:metadata, :comment)
          return nil unless comment

          match = comment.match(CommentVersionHelper::FROZEN_COMMENT_REF_PATTERN)
          return nil unless match

          version_str = match[1].sub(/\Av/i, "")
          return nil unless Dependabot::PreCommit::Version.correct?(version_str)

          Dependabot::PreCommit::Version.new(version_str)
        end

        sig { returns(Dependabot::PreCommit::Helpers::Githelper) }
        def git_helper
          Helpers::Githelper.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            consider_version_branches_pinned: false,
            dependency_source_details: nil
          )
        end
      end
    end
  end
end
