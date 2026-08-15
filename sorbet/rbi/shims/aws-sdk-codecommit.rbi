# typed: strong
# frozen_string_literal: true

module Aws
  module CodeCommit
    module Types
      class GetFolderOutput
        sig { returns(T::Array[Aws::CodeCommit::Types::File]) }
        attr_reader :files
      end

      class BatchGetCommitsOutput
        sig { returns(T.nilable(T::Array[Aws::CodeCommit::Types::Commit])) }
        attr_reader :commits
      end

      class Commit
        sig { returns(T.nilable(Aws::CodeCommit::Types::UserInfo)) }
        attr_reader :author

        sig { returns(T.nilable(String)) }
        attr_reader :message
      end

      class UserInfo
        sig { returns(T.nilable(String)) }
        attr_reader :email

        sig { returns(T.nilable(String)) }
        attr_reader :date
      end

      class GetPullRequestOutput
        sig { returns(Aws::CodeCommit::Types::PullRequest) }
        attr_reader :pull_request
      end

      class PullRequest
        sig { returns(T::Array[Aws::CodeCommit::Types::PullRequestTarget]) }
        attr_reader :pull_request_targets
      end

      class PullRequestTarget
        sig { returns(String) }
        attr_reader :source_reference

        sig { returns(Aws::CodeCommit::Types::MergeMetadata) }
        attr_reader :merge_metadata
      end

      class MergeMetadata
        sig { returns(T::Boolean) }
        attr_reader :is_merged
      end

      class File
        sig { returns(String) }
        attr_reader :relative_path
      end
    end
  end
end
