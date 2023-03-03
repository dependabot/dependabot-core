# typed: strong
# frozen_string_literal: true

module GPGME
  class Crypto
    sig { params(commit_object: String, opts: T.nilable(T::Hash[T.untyped, T.untyped])).returns(GPGME::Data) }
    def sign(commit_object, opts = nil); end
  end
end
