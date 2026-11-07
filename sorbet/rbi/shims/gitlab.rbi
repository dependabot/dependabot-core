# typed: strong
# frozen_string_literal: true

module Gitlab
  class PaginatedResponse
    sig { returns(T.nilable(Gitlab::ObjectifiedHash)) }
    def first; end

    sig { returns(T::Boolean) }
    def any?; end

    sig { returns(T::Array[Gitlab::ObjectifiedHash]) }
    sig do
      params(
        block: T.proc.params(element: Gitlab::ObjectifiedHash).void
      )
        .returns(T::Enumerator[Gitlab::ObjectifiedHash])
    end
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
