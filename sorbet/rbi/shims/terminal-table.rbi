# typed: strong
# frozen_string_literal: true

class Terminal::Table
  sig do
    params(
      options: T::Hash[T.untyped, T.untyped],
      block: T.nilable(T.proc.params(table: Terminal::Table).void)
    ).void
  end
  def initialize(options = {}, &block); end

  sig { params(array: T.untyped).returns(T.self_type) }
  def <<(array); end

  sig { params(title: String).void }
  def title=(title); end

  sig { params(arrays: T.untyped).void }
  def headings=(arrays); end

  sig { params(array: T.untyped).void }
  def rows=(array); end

  sig { returns(String) }
  def to_s; end
end
