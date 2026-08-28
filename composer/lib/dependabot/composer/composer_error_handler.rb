# typed: strict
# frozen_string_literal: true

require "uri"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/shared_helpers"

module Dependabot
  module Composer
    class ComposerErrorHandler
      extend T::Sig

      CURL_ERROR = /curl error 52 while downloading (?<url>.*): Empty reply from server/

      PRIVATE_SOURCE_AUTH_FAIL = T.let(
        [
          /Could not authenticate against (?<url>.*)/,
          /The '(?<url>.*)' URL could not be accessed \(HTTP 403\)/,
          /The "(?<url>.*)" file could not be downloaded/
        ].freeze,
        T::Array[Regexp]
      )

      REQUIREMENT_ERROR = /^(?<req>.*) is invalid, it should not contain uppercase characters/

      UNRESOLVABLE_ERROR_PATTERNS = T.let(
        [
          /^Could not parse version/,
          %r{does not allow connections to http://},
          /The `url` supplied for the path .* does not exist/,
          /^Invalid version string/,
          /^Link constraint in .+ requires > .+ should be a valid version constraint, got /
        ].freeze,
        T::Array[Regexp]
      )

      NO_URL = "No URL specified"

      sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
      def handle_composer_error(error)
        raise DependencyFileNotResolvable, error.message if unresolvable_error?(error)

        PRIVATE_SOURCE_AUTH_FAIL.each do |regex|
          next unless error.message.match?(regex)

          url = T.must(error.message.match(regex)).named_captures["url"]
          sanitized_url = sanitize_uri(T.must(url))
          raise PrivateSourceAuthenticationFailure, sanitized_url.empty? ? NO_URL : sanitized_url
        end

        if error.message.match?(REQUIREMENT_ERROR)
          requirement = T.must(error.message.match(REQUIREMENT_ERROR)).named_captures["req"]
          raise DependencyFileNotResolvable, "Invalid requirement: #{requirement}"
        end

        return unless error.message.match?(CURL_ERROR)

        url = T.must(error.message.match(CURL_ERROR)).named_captures["url"]
        raise PrivateSourceBadResponse, T.must(url)
      end

      sig { params(url: String).returns(String) }
      def sanitize_uri(url)
        url = "http://#{url}" unless url.start_with?("http")
        uri = URI.parse(url)
        host = T.must(uri.host).downcase
        host.start_with?("www.") ? T.must(host[4..]) : host
      end

      private

      sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
      def unresolvable_error?(error)
        UNRESOLVABLE_ERROR_PATTERNS.any? { |pattern| error.message.match?(pattern) }
      end
    end
  end
end
