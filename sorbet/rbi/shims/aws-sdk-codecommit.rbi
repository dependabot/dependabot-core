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
        sig { returns(T::Array[Aws::CodeCommit::Types::Commit]) }
        attr_reader :commits
      end

      class Commit
        sig { returns(Aws::CodeCommit::Types::UserInfo) }
        attr_reader :author

        sig { returns(T.nilable(String)) }
        attr_reader :message
      end

      class UserInfo
        sig { returns(T.nilable(String)) }
        attr_reader :email

        sig { returns(String) }
        attr_reader :date
      end

      class File
        sig { returns(String) }
        attr_reader :relative_path
      end
    end
  end
end
