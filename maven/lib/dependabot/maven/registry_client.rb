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
      def self.get(url:, headers: {}, options: {})
        Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults({ headers: headers }.merge(options))
        )
      end

      def self.head(url:, headers: {}, options: {})
        Excon.head(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults({ headers: headers }.merge(options))
        )
      end
    end
  end
end
