# frozen_string_literal: true

module Dependabot
  module Terraform
    class Helpers

      ARCHIVE_EXTENSIONS = %w(.zip .tbz2 .tgz .txz).freeze

      # rubocop:disable Metrics/PerceivedComplexity
      # See https://www.terraform.io/docs/modules/sources.html#http-urls for
      # details of how Terraform handle HTTP(S) sources for modules
      def self.get_proxied_source(raw_source) # rubocop:disable Metrics/AbcSize
        return raw_source unless raw_source.start_with?("http")

        uri = URI.parse(raw_source.split(%r{(?<!:)//}).first)
        return raw_source if uri.path.end_with?(*ARCHIVE_EXTENSIONS)
        return raw_source if URI.parse(raw_source).query&.include?("archive=")

        url = raw_source.split(%r{(?<!:)//}).first + "?terraform-get=1"
        host = URI.parse(raw_source).host

        response = Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults
        )
        raise PrivateSourceAuthenticationFailure, host if response.status == 401

        return response.headers["X-Terraform-Get"] if response.headers["X-Terraform-Get"]

        doc = Nokogiri::XML(response.body)
        doc.css("meta").find do |tag|
          tag.attributes&.fetch("name", nil)&.value == "terraform-get"
        end&.attributes&.fetch("content", nil)&.value
      rescue Excon::Error::Socket, Excon::Error::Timeout => e
        raise PrivateSourceAuthenticationFailure, host if e.message.include?("no address for")

        raw_source
      end
      # rubocop:enable Metrics/PerceivedComplexity
    end
  end
end
