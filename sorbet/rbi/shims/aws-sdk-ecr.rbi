# typed: strong
# frozen_string_literal: true

module Aws
  module ECR
    module Errors
      class InvalidSignatureException < Aws::Errors::ServiceError; end
      class UnrecognizedClientException < Aws::Errors::ServiceError; end
    end
  end
end
