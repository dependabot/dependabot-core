# typed: strong
# frozen_string_literal: true

module Aws
  module CodeCommit
    module Types
      class GetFolderOutput
        sig { returns(T::Array[Aws::CodeCommit::Types::File]) }
        attr_reader :files
      end

      class File
        sig { returns(String) }
        attr_reader :relative_path
      end
    end
  end
end
