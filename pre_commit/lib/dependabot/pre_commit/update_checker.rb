# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/pre_commit/comment_version_helper"
require "dependabot/pre_commit/requirement"
require "dependabot/pre_commit/version"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/node"
require "dependabot/pre_commit/additional_dependency_checkers/python"
require "dependabot/pre_commit/additional_dependency_checkers/ruby"
require "dependabot/pre_commit/additional_dependency_checkers/go"
require "dependabot/pre_commit/additional_dependency_checkers/rust"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module PreCommit
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        return additional_dependency_latest_version if additional_dependency?

        @latest_version ||= T.let(
          T.must(latest_version_finder).latest_release,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        dependency.version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return additional_dependency_updated_requirements if additional_dependency?

        dependency.requirements.map do |req|
          source = T.cast(req[:source], T.nilable(T::Hash[Symbol, T.untyped]))
          updated = updated_ref(source)
          next req unless updated

          current = T.cast(source&.[](:ref), T.nilable(String))

          # Maintain short git hash when the updated SHA starts with the current SHA
          if T.cast(req[:type], T.nilable(String)) == "git" &&
             git_commit_checker.ref_looks_like_commit_sha?(updated) &&
             current && git_commit_checker.ref_looks_like_commit_sha?(current) &&
             updated.start_with?(current)
            next req
          end

          new_source = T.must(source).merge(ref: updated)
          new_metadata = updated_comment_version_metadata(req, updated)
          req.merge(source: new_source, metadata: new_metadata)
        end
      end

      private

      sig { returns(T.nilable(Dependabot::PreCommit::UpdateChecker::LatestVersionFinder)) }
      def latest_version_finder
        @latest_version_finder ||=
          T.let(
            LatestVersionFinder.new(
              dependency: dependency,
              credentials: credentials,
              dependency_files: dependency_files,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              cooldown_options: update_cooldown
            ),
            T.nilable(Dependabot::PreCommit::UpdateChecker::LatestVersionFinder)
          )
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def current_version
        return super if dependency.numeric_version

        frozen_ver = version_from_comment
        return frozen_ver if frozen_ver

        # For git dependencies, try to parse the version from the ref
        source_details = dependency.source_details(allowed_types: ["git"])
        return nil unless source_details

        ref = T.cast(source_details.fetch(:ref, nil), T.nilable(String))
        return nil unless ref

        version_string = ref.sub(/^v/, "")
        return nil unless version_class.correct?(version_string)

        version_class.new(version_string)
      end

      sig { returns(T::Boolean) }
      def sha1_version_up_to_date?
        frozen_ver = version_from_comment
        return super unless frozen_ver

        resolved_sha = latest_commit_sha
        return true if resolved_sha && resolved_sha == dependency.version

        false
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T.nilable(String)) }
      def latest_commit_for_pinned_ref
        @latest_commit_for_pinned_ref ||= T.let(
          begin
            head_commit_for_ref_sha = git_commit_checker.head_commit_for_pinned_ref
            if head_commit_for_ref_sha
              head_commit_for_ref_sha
            else
              url = T.cast(git_commit_checker.dependency_source_details&.fetch(:url), T.nilable(String))
              source = T.must(Source.from_url(T.must(url)))

              SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
                repo_contents_path = File.join(temp_dir, File.basename(source.repo))

                SharedHelpers.run_shell_command("git clone --no-recurse-submodules #{url} #{repo_contents_path}")

                Dir.chdir(repo_contents_path) do
                  ref = T.cast(git_commit_checker.dependency_source_details&.fetch(:ref), T.nilable(String))
                  ref_branch = find_container_branch(T.must(ref))
                  git_commit_checker.head_commit_for_local_branch(ref_branch) if ref_branch
                end
              end
            end
          end,
          T.nilable(String)
        )
      end

      sig { params(source: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(String)) }
      def updated_ref(source)
        return unless git_commit_checker.git_dependency?

        source_git_commit_checker = git_helper.git_commit_checker_for(source)

        # Return the git tag if updating a pinned version
        if source_git_commit_checker.pinned_ref_looks_like_version? &&
           (new_tag = T.must(latest_version_finder).latest_version_tag)
          return T.cast(new_tag.fetch(:tag), String)
        end

        # Return the pinned git commit if one is available
        if source_git_commit_checker.pinned_ref_looks_like_commit_sha? &&
           (new_commit_sha = latest_commit_sha)
          return new_commit_sha
        end

        nil
      end

      sig { returns(T.nilable(String)) }
      def latest_commit_sha
        new_tag = T.must(latest_version_finder).latest_version_tag

        if new_tag
          if version_from_comment || git_commit_checker.local_tag_for_pinned_sha
            return T.cast(new_tag.fetch(:commit_sha), String)
          end

          return latest_commit_for_pinned_ref
        end

        # If there's no tag but we have a latest_version (commit SHA), use it
        latest_ver = latest_version
        return latest_ver if latest_ver.is_a?(String)

        nil
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(git_helper.git_commit_checker, T.nilable(Dependabot::GitCommitChecker))
      end

      sig do
        params(
          req: T::Hash[Symbol, T.untyped],
          new_ref: String
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def updated_comment_version_metadata(req, new_ref)
        existing_metadata = T.cast(req.fetch(:metadata, {}), T::Hash[Symbol, T.untyped])
        comment = T.cast(existing_metadata[:comment], T.nilable(String))
        return existing_metadata unless comment

        old_version = extract_version_from_comment(comment)
        return existing_metadata unless old_version

        new_version = resolve_new_comment_version(new_ref)
        return existing_metadata unless new_version

        existing_metadata.merge(comment_version: old_version, new_comment_version: new_version)
      end

      sig { params(comment: String).returns(T.nilable(String)) }
      def extract_version_from_comment(comment)
        match = comment.match(CommentVersionHelper::COMMENT_VERSION_PATTERN)
        match&.[](0)
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def version_from_comment
        @version_from_comment ||= T.let(
          begin
            comment = @dependency.requirements.
              map { |req| T.cast(req.fetch(:metadata, {}), T::Hash[Symbol, T.untyped])[:comment] }.
              compact.
              first
            return nil unless comment

            version_string = extract_version_from_comment(comment)
            return nil unless version_string

            cleaned = version_string.sub(/^v/, "")
            return nil unless version_class.correct?(cleaned)

            version_class.new(cleaned)
          end,
          T.nilable(Dependabot::Version)
        )
      end

      sig { params(new_ref: String).returns(T.nilable(String)) }
      def resolve_new_comment_version(new_ref)
        new_tag = T.must(latest_version_finder).latest_version_tag
        return new_tag&.fetch(:tag, nil) if new_tag

        nil
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

      # Additional dependency support methods

      sig { returns(T::Boolean) }
      def additional_dependency?
        requirement = dependency.requirements.first
        return false unless requirement

        source = T.cast(requirement[:source], T.nilable(T::Hash[Symbol, T.untyped]))
        return false unless source

        T.cast(source[:type], T.nilable(String)) == "additional_dependency"
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def additional_dependency_latest_version
        source = T.cast(dependency.requirements.first&.dig(:source), T::Hash[Symbol, T.untyped])
        language = T.cast(source[:language], T.nilable(String))
        return nil unless language && AdditionalDependencyCheckers.supported?(language)

        checker = additional_dependency_checker(language, source)
        return nil unless checker

        latest = checker.latest_version
        Dependabot.logger.info("Latest version for #{dependency.name}: #{latest || 'none'}")

        latest
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def additional_dependency_updated_requirements
        source = T.cast(dependency.requirements.first&.dig(:source), T::Hash[Symbol, T.untyped])
        language = T.cast(source[:language], T.nilable(String))
        return dependency.requirements unless language && AdditionalDependencyCheckers.supported?(language)

        checker = additional_dependency_checker(language, source)
        return dependency.requirements unless checker

        latest = checker.latest_version
        return dependency.requirements unless latest

        checker.updated_requirements(latest)
      end

      sig do
        params(
          language: String,
          source: T::Hash[Symbol, T.untyped]
        ).returns(T.nilable(Dependabot::PreCommit::AdditionalDependencyCheckers::Base))
      end
      def additional_dependency_checker(language, source)
        checker_class = AdditionalDependencyCheckers.for_language(language)
        checker_class.new(
          source: source,
          credentials: credentials,
          requirements: dependency.requirements,
          current_version: dependency.version
        )
      rescue StandardError => e
        Dependabot.logger.error("Error creating checker for #{language}: #{e.message}")
        nil
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("pre_commit", Dependabot::PreCommit::UpdateChecker)
