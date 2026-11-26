# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"
require "time"
require "uri"

require "dependabot/logger"
require "dependabot/shared_helpers"

module Dependabot
  module AzurePipelines
    module Package
      # Sends requests to Azure DevOps and the Marketplace.
      #
      # Both services throttle (429) and have short outages (5xx, or their "Our
      # services aren't available right now" page). Excon only retries socket errors
      # and timeouts, without waiting in between, so those are retried here with
      # exponential backoff that respects Retry-After. Anything else, including an
      # authentication failure or an error the service explains (`TFxxxxxx`, or a
      # JSON body with a `typeKey`), is returned straight away: asking again would get
      # the same answer.
      module AzureDevOpsHttp
        extend T::Sig

        MAX_ATTEMPTS = T.let(4, Integer)
        BASE_DELAY_SECONDS = T.let(1.0, Float)
        MAX_DELAY_SECONDS = T.let(30.0, Float)
        RETRYABLE_STATUSES = T.let([429, 500, 502, 503, 504].freeze, T::Array[Integer])
        OUTAGE_PAGE = T.let(/Our services aren't available right now/i, Regexp)
        SERVICE_ERROR = T.let(/\b(TF\d{4,}:[^<\r\n]*)/i, Regexp)

        # Without this, Azure DevOps turns a missing or expired credential into a
        # redirect to its interactive sign-in page instead of a 401.
        HEADERS = T.let(
          {
            "Accept" => "application/json",
            "User-Agent" => "dependabot-core",
            "X-TFS-FedAuthRedirect" => "Suppress"
          }.freeze,
          T::Hash[String, String]
        )

        class << self
          extend T::Sig

          sig { params(url: String, headers: T::Hash[String, String]).returns(Excon::Response) }
          def get(url:, headers: {})
            request(:get, url, headers: headers)
          end

          sig { params(url: String, body: String, headers: T::Hash[String, String]).returns(Excon::Response) }
          def post(url:, body:, headers: {})
            request(:post, url, headers: headers, body: body)
          end

          # The service's own explanation of a failed response, for error messages.
          sig { params(response: Excon::Response).returns(T.nilable(String)) }
          def service_message(response)
            body = response.body.to_s.delete("\uFEFF")
            json_message(body) || body[SERVICE_ERROR, 1]&.strip
          end

          sig { params(response: Excon::Response).returns(String) }
          def describe_failure(response)
            message = service_message(response)
            message ? "HTTP #{response.status}: #{message}" : "HTTP #{response.status}"
          end

          sig { params(seconds: Float).void }
          def wait(seconds)
            Kernel.sleep(seconds)
          end

          private

          sig do
            params(method: Symbol, url: String, headers: T::Hash[String, String], body: T.nilable(String))
              .returns(Excon::Response)
          end
          def request(method, url, headers:, body: nil)
            attempt = 1
            loop do
              response = attempt_request(method, url, headers, body, final: attempt == MAX_ATTEMPTS)
              return response if response && (attempt == MAX_ATTEMPTS || !retryable?(response))

              delay = retry_delay(response, attempt)
              Dependabot.logger.info(
                "Azure DevOps request to #{sanitized(url)} " \
                "#{response ? "got HTTP #{response.status}" : 'failed to connect'}; " \
                "retrying in #{delay.round(1)}s (attempt #{attempt + 1} of #{MAX_ATTEMPTS})"
              )
              wait(delay)
              attempt += 1
            end
          end

          sig do
            params(
              method: Symbol,
              url: String,
              headers: T::Hash[String, String],
              body: T.nilable(String),
              final: T::Boolean
            ).returns(T.nilable(Excon::Response))
          end
          def attempt_request(method, url, headers, body, final:)
            options = SharedHelpers.excon_defaults(
              headers: HEADERS.merge(headers),
              idempotent: true,
              retry_limit: 1
            )
            options[:body] = body if body
            Excon.public_send(method, url, **options)
          rescue Excon::Error::Timeout, Excon::Error::Socket
            raise if final

            nil
          end

          sig { params(response: Excon::Response).returns(T::Boolean) }
          def retryable?(response)
            RETRYABLE_STATUSES.include?(response.status) || response.body.to_s.match?(OUTAGE_PAGE)
          end

          sig { params(response: T.nilable(Excon::Response), attempt: Integer).returns(Float) }
          def retry_delay(response, attempt)
            requested = response && retry_after(response)
            return [requested, MAX_DELAY_SECONDS].min if requested

            exponential = (BASE_DELAY_SECONDS * (2**(attempt - 1))).to_f
            [exponential + (rand * BASE_DELAY_SECONDS), MAX_DELAY_SECONDS].min
          end

          sig { params(response: Excon::Response).returns(T.nilable(Float)) }
          def retry_after(response)
            value = (response.headers["Retry-After"] || response.headers["retry-after"]).to_s.strip
            return nil if value.empty?
            return [value.to_f, 0.0].max if value.match?(/\A\d+(?:\.\d+)?\z/)

            [Time.httpdate(value) - Time.now, 0.0].max
          rescue ArgumentError
            nil
          end

          sig { params(body: String).returns(T.nilable(String)) }
          def json_message(body)
            parsed = JSON.parse(body)
            return nil unless parsed.is_a?(Hash)
            return nil unless %w(typeKey typeName eventId).any? { |key| parsed.key?(key) }

            message = parsed["message"]
            return message.strip if message.is_a?(String) && !message.strip.empty?

            (parsed["typeKey"] || parsed["typeName"] || parsed["eventId"]).to_s
          rescue JSON::ParserError
            nil
          end

          sig { params(url: String).returns(String) }
          def sanitized(url)
            uri = URI.parse(url)
            "#{uri.scheme}://#{uri.host}#{uri.path}"
          rescue URI::InvalidURIError
            "(invalid URL)"
          end
        end
      end
    end
  end
end
