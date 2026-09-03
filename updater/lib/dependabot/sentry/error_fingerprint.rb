# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

module Dependabot
  module Sentry
    module ErrorFingerprint
      extend T::Sig

      CALL_SITE_PATTERN = %r{
        (?<path>[^/]+/lib/dependabot/[^:]+\.rb):\d+:in\s+[`'](?<method>[^`']+)
      }x
      REGISTRY_CLIENT_PATH = "common/lib/dependabot/registry_client.rb"

      sig do
        params(
          error: StandardError,
          package_manager: T.nilable(String)
        ).returns(T.nilable(T::Array[String]))
      end
      def self.for(error:, package_manager:)
        return unless eof_socket_error?(error)

        [
          "excon-eof",
          package_manager || "unknown-package-manager",
          dependabot_call_site(error) || "unknown-call-site"
        ]
      end

      sig { params(error: StandardError).returns(T::Boolean) }
      private_class_method def self.eof_socket_error?(error)
        return false unless error.is_a?(Excon::Error::Socket)

        case error.socket_error
        when EOFError then true
        else false
        end
      end

      sig { params(error: StandardError).returns(T.nilable(String)) }
      private_class_method def self.dependabot_call_site(error)
        error.backtrace&.each do |frame|
          match = frame.match(CALL_SITE_PATTERN)
          next unless match
          next if match[:path] == REGISTRY_CLIENT_PATH

          return "#{match[:path]}:#{match[:method]}"
        end

        nil
      end
    end
  end
end
