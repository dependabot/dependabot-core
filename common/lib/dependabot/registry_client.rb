# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/shared_helpers"

# This class provides a thin wrapper around our normal usage of Excon as a simple HTTP client in order to
# provide some minor caching functionality.
#
# This is not used to support full response caching currently, we just use it to ensure we detect unreachable
# hosts and fast-fail on any subsequent requests to them to avoid excessive use of retries and connect- or
# read-timeouts as some jobs tend to be sensitive to exceeding our overall 45 minute timeout.
module Dependabot
  class RegistryClient
    extend T::Sig

    @cached_errors = T.let({}, T::Hash[T.nilable(String), Excon::Error::Timeout])

    sig do
      params(
        url: String,
        headers: T::Hash[T.any(String, Symbol), T.untyped],
        options: T::Hash[Symbol, T.untyped]
      )
        .returns(Excon::Response)
    end
    def self.get(url:, headers: {}, options: {})
      raise T.must(cached_error_for(url)) if cached_error_for(url)

      Excon.get(
        url,
        idempotent: true,
        **SharedHelpers.excon_defaults({ headers: headers }.merge(options))
      )
    rescue Excon::Error::Timeout => e
      cache_error(url, e)
      raise e
    end

    sig do
      params(
        url: String,
        headers: T::Hash[T.any(String, Symbol), T.untyped],
        options: T::Hash[Symbol, T.untyped]
      )
        .returns(Excon::Response)
    end
    def self.head(url:, headers: {}, options: {})
      raise T.must(cached_error_for(url)) if cached_error_for(url)

      Excon.head(
        url,
        idempotent: true,
        **SharedHelpers.excon_defaults({ headers: headers }.merge(options))
      )
    rescue Excon::Error::Timeout => e
      cache_error(url, e)
      raise e
    end

    sig { void }
    def self.clear_cache!
      @cached_errors = {}
    end

    sig { params(url: String, error: Excon::Error::Timeout).void }
    private_class_method def self.cache_error(url, error)
      host = URI(url).host
      @cached_errors[host] = error
    end

    sig { params(url: String).returns(T.nilable(Excon::Error::Timeout)) }
    private_class_method def self.cached_error_for(url)
      host = URI(url).host
      @cached_errors.fetch(host, nil)
    end
  end
end
