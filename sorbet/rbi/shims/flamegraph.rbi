# typed: strong
# frozen_string_literal: true

class Flamegraph
  sig do
    type_parameters(:U)
      .params(
        path: String,
        block: T.proc.returns(T.type_parameter(:U))
      )
      .returns(T.type_parameter(:U))
  end
  def self.generate(path, &block); end
end
