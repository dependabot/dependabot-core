# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

module Dependabot
  module NpmAndYarn
    module ErrorSanitizer
      extend T::Sig

      URL_REGEX = T.let(%r{https?://[^\s"']+}i, Regexp)
      USERINFO_REGEX = T.let(%r{\A(https?://)[^/\s@]+@}i, Regexp)
      URL_USERINFO_REGEX = T.let(%r{(https?://)[^/\s@]+@}i, Regexp)
      TOKEN_QUERY_REGEX = T.let(%r{([?&](?:access_token|authToken|token|password)=)[^&\s"']+}i, Regexp)
      NPM_AUTH_CONFIG_REGEX = T.let(%r{((?:_authToken|_auth|password)\s*=\s*)[^\s"']+}i, Regexp)

      sig { params(message: T.nilable(String)).returns(String) }
      def self.redact_credentials(message)
        message.to_s
               .gsub(URL_USERINFO_REGEX) { "#{T.must(Regexp.last_match)[1]}<redacted>@" }
               .gsub(TOKEN_QUERY_REGEX) { "#{T.must(Regexp.last_match)[1]}<redacted>" }
               .gsub(NPM_AUTH_CONFIG_REGEX) { "#{T.must(Regexp.last_match)[1]}<redacted>" }
      end

      sig { params(message: T.nilable(String)).returns(String) }
      def self.host_from_url_or_message(message)
        candidate = URI.extract(message.to_s, %w[http https]).first || message.to_s
        sanitized = strip_url_userinfo(URI.decode_www_form_component(candidate)).chomp(":")

        return uri_host(sanitized) if sanitized.match?(URL_REGEX)

        sanitized.sub(/\A[^@\s\/]+@/, "").split(/[\/\s]/).first.to_s
      rescue URI::InvalidURIError
        fallback_host(message.to_s)
      end

      sig { params(url: String).returns(String) }
      def self.strip_url_userinfo(url)
        url.gsub(USERINFO_REGEX) { T.must(Regexp.last_match)[1].to_s }
      end

      sig { params(url: String).returns(String) }
      def self.redacted_url(url)
        redact_credentials(url).gsub(%r{\A(https?://)<redacted>@}i) { T.must(Regexp.last_match)[1].to_s }
      end

      sig { params(url: String).returns(String) }
      def self.uri_host(url)
        uri = URI.parse(url)
        return fallback_host(url) unless uri.host

        default_port = uri.scheme == "https" ? 443 : 80
        return uri.host if uri.port == default_port

        "#{uri.host}:#{uri.port}"
      rescue URI::InvalidURIError
        fallback_host(url)
      end
      private_class_method :uri_host

      sig { params(message: String).returns(String) }
      def self.fallback_host(message)
        message
          .sub(%r{\Ahttps?://}i, "")
          .sub(/\A[^@\s\/]+@/, "")
          .split(/[\/\s]/)
          .first
          .to_s
      end
      private_class_method :fallback_host
    end
  end
end
