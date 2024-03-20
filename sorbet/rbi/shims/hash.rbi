# typed: strong
# frozen_string_literal: true

class Hash
  extend T::Generic

  sig { returns(String) }
  def to_json; end

  sig { returns(Integer) }
  def hash; end

  sig { returns(T::Hash[K, V]) }
  def compact; end
end
