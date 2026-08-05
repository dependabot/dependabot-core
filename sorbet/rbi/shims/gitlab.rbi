# typed: strong
# frozen_string_literal: true

class Gitlab::PaginatedResponse
  sig do
    type_parameters(:U)
      .params(
        blk: T.proc.params(element: Object).returns(T.nilable(T.type_parameter(:U)))
      )
      .returns(T::Array[T.type_parameter(:U)])
  end
  def filter_map(&blk); end
end
