# frozen_string_literal: true

require "dependabot/shared_helpers"

# This class provides a thin wrapper around our normal usage of Excon as a simple HTTP client in order to
# provide some minor caching functionality.
#
# This is not used to support full response caching currently, we just use it to ensure we detect unreachable
# hosts and fast-fail on any subsequent requests to them to avoid excessive use of retries and connect- or
# read-timeouts as Maven jobs tend to be sensitive to exceeding our overall 45 minute timeout.
module Dependabot
  module Maven
    class RegistryClient
      @@cached_errors = {}

      def self.get(url:, headers: {}, options: {})
        raise cached_error_for(url) if cached_error_for(url)

        Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults({ headers: headers }.merge(options))
        )
      rescue Excon::Error::Timeout => error
        cache_error(url, error)
        raise error
      end

      def self.head(url:, headers: {}, options: {})
        raise cached_error_for(url) if cached_error_for(url)

        Excon.head(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults({ headers: headers }.merge(options))
        )
      rescue Excon::Error::Timeout => error
        cache_error(url, error)
        raise error
      end

      def self.clear_cache!
        @@cached_errors = {}
      end

      private_class_method def self.cache_error(url, error)
        host = URI(url).host
        @@cached_errors[host] = error
      end

      private_class_method def self.cached_error_for(url)
        host = URI(url).host
        @@cached_errors.fetch(host, nil)
      end
    end
  end
end
