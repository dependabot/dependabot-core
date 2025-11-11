# typed: strong
# frozen_string_literal: true

class Hash
  extend T::Generic

  sig { params(args: T.untyped).returns(String) }
  def to_json(*args); end

  sig { returns(Integer) }
  def hash; end

  sig { returns(T::Hash[K, V]) }
  def compact; end
end
