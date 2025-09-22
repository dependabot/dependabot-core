# typed: strong
# frozen_string_literal: true

module Excon
  class << self
    sig do
      params(
        url: String,
        params: T::Hash[Symbol, T.untyped],
        block: T.nilable(T.proc.void)
      )
        .returns(Excon::Response)
    end
    def get(url, params = {}, &block); end

    sig do
      params(
        url: String,
        params: T::Hash[Symbol, T.untyped],
        block: T.nilable(T.proc.void)
      )
        .returns(Excon::Response)
    end
    def head(url, params = {}, &block); end
  end

  class Response
    sig { returns(Integer) }
    def status; end

    sig { returns(Excon::Headers) }
    def headers; end

    sig { returns(String) }
    def body; end
  end

  class Headers
    sig { params(key: T.any(String, Symbol)).returns(T.nilable(String)) }
    def [](key); end
  end
end
