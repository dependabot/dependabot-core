# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/pre_commit/comment_version_helper"
require "dependabot/pre_commit/helpers"
require "dependabot/pre_commit/requirement"
require "dependabot/pre_commit/update_checker"
require "dependabot/pre_commit/version"
require "dependabot/shared_helpers"

module Dependabot
  module PreCommit
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          credentials:,
          ignored_versions: [],
          raise_on_ignored: false
        )
          @dependency = dependency
          @credentials = credentials
          @raise_on_ignored = raise_on_ignored
          @ignored_versions = ignored_versions

          @git_helper = T.let(git_helper, Dependabot::PreCommit::Helpers::Githelper)
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def release_list_for_git_dependency
          return unless git_dependency?
          return current_commit unless git_commit_checker.pinned?

          version_tag_release || commit_sha_release
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def version_tag_release
          return unless git_commit_checker.pinned_ref_looks_like_version? && latest_version_tag

          latest_version = latest_version_tag&.fetch(:version)
          return current_version if shortened_semver_eq?(dependency.version, latest_version.to_s)

          latest_version
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def commit_sha_release
          return unless git_commit_checker.pinned_ref_looks_like_commit_sha?

          if latest_version_tag
            if git_commit_checker.local_tag_for_pinned_sha || version_comment?
              return T.must(latest_version_tag).fetch(:version)
            end

            return latest_commit_for_pinned_ref
          end

          latest_commit_for_pinned_ref
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          @latest_version_tag ||= T.let(
            begin
              if dependency.version.nil? || !Dependabot::PreCommit::Version.correct?(dependency.version)
                return constrained_latest_version_tag || git_commit_checker.local_tag_for_latest_version
              end

              ref = git_commit_checker.local_ref_for_latest_version_matching_existing_precision
              return ref if ref && current_version && ref.fetch(:version) > current_version

              git_commit_checker.local_ref_for_latest_version_lower_precision
            end,
            T.nilable(T::Hash[Symbol, T.untyped])
          )
        end

        private

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def constrained_latest_version_tag
          frozen_ref = frozen_comment_ref
          return nil unless frozen_ref

          prefix = tag_prefix(frozen_ref)
          return nil if prefix.empty?

          version_suffix = frozen_ref.sub(/^#{Regexp.escape(prefix)}/, "")
          return nil if version_suffix.empty? || version_suffix !~ /^\d/

          matching = tags_matching_frozen_constraint(prefix, version_suffix.split("."))
          git_commit_checker.max_local_tag(matching)
        end

        sig do
          params(
            prefix: String,
            frozen_segments: T::Array[String]
          ).returns(T::Array[Dependabot::GitRef])
        end
        def tags_matching_frozen_constraint(prefix, frozen_segments)
          tags = tags_with_prefix(prefix)

          max_segments = tags.map { |t| tag_version_segments(t.name, prefix).length }.max || 0
          return tags unless frozen_segments.length < max_segments

          tags.select { |tag| tag_starts_with_segments?(tag.name, prefix, frozen_segments) }
        end

        sig { params(prefix: String).returns(T::Array[Dependabot::GitRef]) }
        def tags_with_prefix(prefix)
          git_commit_checker.allowed_version_tags.select { |tag| tag.name.start_with?(prefix) }
        end

        sig { params(tag_name: String, prefix: String).returns(T::Array[String]) }
        def tag_version_segments(tag_name, prefix)
          tag_name.sub(/^#{Regexp.escape(prefix)}/, "").split(".")
        end

        sig { params(tag_name: String, prefix: String, frozen_segments: T::Array[String]).returns(T::Boolean) }
        def tag_starts_with_segments?(tag_name, prefix, frozen_segments)
          segments = tag_version_segments(tag_name, prefix)
          frozen_segments.each_with_index.all? { |seg, i| segments[i] == seg }
        end

        sig { returns(T.nilable(String)) }
        def frozen_comment_ref
          comment = dependency.requirements.first&.dig(:metadata, :comment)
          return nil unless comment

          match = comment.match(CommentVersionHelper::FROZEN_COMMENT_REF_PATTERN)
          match&.[](1)
        end

        sig { params(ref: String).returns(String) }
        def tag_prefix(ref)
          ref.sub(/\d+(?:\.\d+)*$/, "")
        end

        sig { returns(T::Boolean) }
        def version_comment?
          comment = dependency.requirements.first&.dig(:metadata, :comment)
          return false unless comment

          comment.match?(CommentVersionHelper::COMMENT_VERSION_PATTERN)
        end

        sig { returns(T.nilable(String)) }
        def current_commit
          git_commit_checker.head_commit_for_current_branch
        end

        sig { params(base: T.nilable(String), other: T.nilable(String)).returns(T::Boolean) }
        def shortened_semver_eq?(base, other)
          return false unless base && other

          base_split = base.split(".")
          other_split = other.split(".")
          return false unless base_split.length <= other_split.length

          other_split[0..(base_split.length - 1)] == base_split
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_version
          @current_version ||= T.let(dependency.numeric_version, T.nilable(Dependabot::Version))
        end

        sig { returns(T.nilable(String)) }
        def latest_commit_for_pinned_ref
          @latest_commit_for_pinned_ref ||= T.let(
            begin
              head_commit_for_ref_sha = git_commit_checker.head_commit_for_pinned_ref
              if head_commit_for_ref_sha
                head_commit_for_ref_sha
              else
                url = git_commit_checker.dependency_source_details&.fetch(:url)
                source = T.must(Source.from_url(url))

                SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
                  repo_contents_path = File.join(temp_dir, File.basename(source.repo))

                  SharedHelpers.run_shell_command("git clone --no-recurse-submodules #{url} #{repo_contents_path}")

                  Dir.chdir(repo_contents_path) do
                    ref_branch = find_container_branch(git_commit_checker.dependency_source_details&.fetch(:ref))
                    git_commit_checker.head_commit_for_local_branch(ref_branch) if ref_branch
                  end
                end
              end
            end,
            T.nilable(String)
          )
        end

        sig { params(sha: String).returns(T.nilable(String)) }
        def find_container_branch(sha)
          branches_including_ref = SharedHelpers.run_shell_command(
            "git branch --remotes --contains #{sha}",
            fingerprint: "git branch --remotes --contains <sha>"
          ).split("\n").map { |branch| branch.strip.gsub("origin/", "") }
          return if branches_including_ref.empty?

          current_branch = branches_including_ref.find { |branch| branch.start_with?("HEAD -> ") }

          if current_branch
            current_branch.delete_prefix("HEAD -> ")
          elsif branches_including_ref.size > 1
            raise "Multiple ambiguous branches (#{branches_including_ref.join(', ')}) include #{sha}!"
          else
            branches_including_ref.first
          end
        end

        sig do
          params(tags_array: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def filter_lower_tags(tags_array)
          return tags_array unless current_version

          tags_array.select { |tag| tag.fetch(:version) > current_version }
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          git_commit_checker.git_dependency?
        end

        sig { returns(Dependabot::GitCommitChecker) }
        def git_commit_checker
          @git_commit_checker ||= T.let(git_helper.git_commit_checker, T.nilable(Dependabot::GitCommitChecker))
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
