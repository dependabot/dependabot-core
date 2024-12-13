# typed: strong
# frozen_string_literal: true

module Excon
  class << self
    sig do
      params(
        url: String,
        params: T.untyped,
        block: T.untyped
      )
        .returns(Excon::Response)
    end
    def get(url, params = T.unsafe(nil), &block); end

    sig do
      params(
        url: String,
        params: T.untyped,
        block: T.untyped
      )
        .returns(Excon::Response)
    end
    def head(url, params = T.unsafe(nil), &block); end
  end

  class Response
    sig { returns(Integer) }
    def status; end

    sig { returns(Excon::Headers) }
    def headers; end
  end

  class Headers
    sig { params(key: String).returns(T.nilable(String)) }
    def [](key); end
  end
end
