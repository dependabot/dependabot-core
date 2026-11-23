# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"
require "dependabot/error_report_context"
require "dependabot/errors"

module Dependabot
  module Cargo
    # Registries can answer with non-JSON error bodies (e.g. a 403 with a plain
    # `Forbidden` body), which would otherwise surface as unknown JSON parse errors.
    module RegistryResponse
      extend T::Sig

      AUTH_FAILURE_STATUSES = [401, 403].freeze

      sig { params(response: Excon::Response, source: String).void }
      def self.raise_for_error_status!(response, source)
        return if (200..299).cover?(response.status)

        raise PrivateSourceAuthenticationFailure, source if AUTH_FAILURE_STATUSES.include?(response.status)

        raise PrivateSourceBadResponse, source
      end

      # Only the host is attached: registry paths can contain private crate names.
      sig do
        type_parameters(:R)
          .params(response: Excon::Response, url: String, blk: T.proc.returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def self.with_parse_error_context(response, url, &blk)
        yield
      rescue JSON::ParserError => e
        ErrorReportContext.attach(
          e,
          { http_method: "GET", host: ErrorReportContext.host_for(url), http_status: response.status }
        )
        raise
      end
    end
  end
end
