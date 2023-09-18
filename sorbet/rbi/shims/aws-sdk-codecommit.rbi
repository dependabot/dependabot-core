# typed: strong
# frozen_string_literal: true

module Aws
  module CodeCommit
    class Client
      class << self
        def new(*_arg0); end
      end
    end

    module Errors
      class BranchDoesNotExistException < Aws::Errors::ServiceError; end

      class FileDoesNotExistException < Aws::Errors::ServiceError; end
    end
  end
end
