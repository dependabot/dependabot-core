# typed: strict
# frozen_string_literal: true

module WebMock
  module Matchers
    sig { params(method: T.any(String, Symbol), uri: T.anything).returns(WebMock::WebMockMatcher) }
    def have_requested(method, uri); end # rubocop:disable Naming/PredicatePrefix -- WebMock's matcher API.

    sig { returns(WebMock::RequestPatternMatcher) }
    def have_been_made; end # rubocop:disable Naming/PredicatePrefix -- WebMock's matcher API.
  end

  class WebMockMatcher
    sig { returns(T.self_type) }
    def once; end
  end

  class RequestPatternMatcher
    sig { returns(T.self_type) }
    def once; end
  end
end
