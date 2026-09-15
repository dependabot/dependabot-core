# typed: strong
# frozen_string_literal: true

require "dependabot/github_actions/file_updater/workflow_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        class VersionCommenter
          extend T::Sig

          sig do
            params(
              dependency: Dependabot::Dependency,
              credentials: T::Array[Dependabot::Credential]
            ).void
          end
          def initialize(dependency:, credentials:)
            @dependency = dependency
            @credentials = credentials
          end

          sig { params(comment: String, old_ref: String, new_ref: String).returns(T.nilable(String)) }
          def updated_comment(comment, old_ref, new_ref)
            comment = comment.rstrip
            previous_version = previous_version_from_comment(comment, old_ref, new_ref)
            return unless previous_version

            new_version_tag = git_checker.most_specific_version_tag_for_sha(new_ref)
            return unless new_version_tag

            new_version = version_class.new(new_version_tag).to_s
            comment.gsub(previous_version, new_version)
          end

          sig { params(comment: String, old_ref: String, new_ref: String).returns(T::Boolean) }
          def recognized_comment?(comment, old_ref, new_ref)
            !previous_version_from_comment(comment.rstrip, old_ref, new_ref).nil?
          end

          sig { params(old_ref: String, new_ref: String).returns(T.nilable(String)) }
          def new_comment(old_ref, new_ref)
            return unless tag_to_sha?(old_ref, new_ref)

            comment_for_ref(new_ref)
          end

          sig { params(ref: String).returns(T.nilable(String)) }
          def comment_for_ref(ref)
            return unless sha?(ref)

            version_tag = git_checker.most_specific_version_tag_for_sha(ref)
            return unless version_tag

            " # #{version_tag}"
          end

          sig { params(ref: String).returns(T::Boolean) }
          def sha?(ref)
            git_checker.ref_looks_like_commit_sha?(ref)
          end

          private

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(T::Array[Dependabot::Credential]) }
          attr_reader :credentials

          sig { params(comment: String, old_ref: String, new_ref: String).returns(T.nilable(String)) }
          def previous_version_from_comment(comment, old_ref, new_ref)
            version_tags = if sha?(old_ref)
                             git_checker.most_specific_version_tags_for_sha(old_ref)
                           elsif tag_to_sha?(old_ref, new_ref)
                             version_tags_for_ref(old_ref)
                           else
                             []
                           end

            version_tags
              .filter_map { |tag| version_class.new(tag).to_s if version_class.correct?(tag) }
              .select { |version| comment.end_with?(version) }
              .max_by(&:length)
          end

          sig { params(ref: String).returns(T::Array[String]) }
          def version_tags_for_ref(ref)
            tags = [ref]
            commit_sha = git_checker.head_commit_for_local_branch(ref)
            tags.concat(git_checker.most_specific_version_tags_for_sha(commit_sha)) if commit_sha
            tags.uniq
          end

          sig { params(old_ref: String, new_ref: String).returns(T::Boolean) }
          def tag_to_sha?(old_ref, new_ref)
            version_class.correct?(old_ref) && sha?(new_ref)
          end

          sig { returns(Dependabot::GitCommitChecker) }
          def git_checker
            @git_checker ||= T.let(
              Dependabot::GitCommitChecker.new(dependency: dependency, credentials: credentials),
              T.nilable(Dependabot::GitCommitChecker)
            )
          end

          sig { returns(T.class_of(Dependabot::GithubActions::Version)) }
          def version_class
            GithubActions::Version
          end
        end
      end
    end
  end
end
