# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    module Package
      # Tells a registry that cannot be reached from one that failed once. The Dependabot proxy closes the
      # connection without a response when it cannot connect to a registry, and it does the same for a moment's
      # trouble, so one failed request does not show that the network the job runs on blocks the registry.
      #
      # This asks the registry again, once, with short timeouts and without Excon's retries. It goes around
      # RegistryClient, whose per-host failure cache would answer for it. Any response at all, whatever its status,
      # means the network path works.
      class RegistryReachability
        extend T::Sig

        PROBE_TIMEOUT_IN_SECONDS = 5

        @unreachable_hosts = T.let({}, T::Hash[String, T::Boolean])

        sig { params(url: String).returns(T::Boolean) }
        def self.reachable?(url)
          host = URI.parse(url).host.to_s
          return false if @unreachable_hosts.key?(host)

          reachable = probe(url)
          # Only a failure is remembered, so a blocked runner is not asked once per dependency. An answer says nothing
          # about the next failure, which is asked about again.
          @unreachable_hosts[host] = true unless reachable
          reachable
        end

        sig { void }
        def self.clear_cache!
          @unreachable_hosts = {}
        end

        sig { params(url: String).returns(T::Boolean) }
        private_class_method def self.probe(url)
          Excon.head(
            url,
            **SharedHelpers.excon_defaults(
              {
                connect_timeout: PROBE_TIMEOUT_IN_SECONDS,
                write_timeout: PROBE_TIMEOUT_IN_SECONDS,
                read_timeout: PROBE_TIMEOUT_IN_SECONDS,
                retry_limit: 0
              }
            )
          )
          true
        rescue Excon::Error::Timeout, Excon::Error::Socket
          false
        end
      end
    end
  end
end
