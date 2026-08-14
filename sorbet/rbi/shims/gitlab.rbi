# typed: strong
# frozen_string_literal: true

module Gitlab
  class PaginatedResponse
    sig { params(block: T.nilable(Proc)).returns(T::Array[Gitlab::ObjectifiedHash]) }
    def auto_paginate(&block); end

    sig do
      type_parameters(:U)
        .params(
          blk: T.proc.params(element: Gitlab::ObjectifiedHash)
                .returns(T.type_parameter(:U))
        )
        .returns(T::Array[T.type_parameter(:U)])
    end
    def map(&blk); end

    sig do
      type_parameters(:U)
        .params(
          blk: T.proc.params(element: Object).returns(T.nilable(T.type_parameter(:U)))
        )
        .returns(T::Array[T.type_parameter(:U)])
    end
    def filter_map(&blk); end
  end
end
