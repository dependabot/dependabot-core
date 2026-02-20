# typed: strict
# frozen_string_literal: true

require "excon"
require "uri"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      MAIN_PYPI_URL = "https://pypi.org/pypi"
      PYPI_INTEGRITY_URL = "https://pypi.org/integrity"

      sig do
        params(
          dependency: Dependabot::Dependency,
          credentials: T::Array[Dependabot::Credential]
        )
          .void
      end
      def initialize(dependency:, credentials:)
        super
        @pypi_listing = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        @pypi_version_listings = T.let({}, T::Hash[String, T::Hash[String, T.untyped]])
      end

      sig { returns(T.nilable(String)) }
      def homepage_url
        pypi_listing.dig("info", "home_page") ||
          pypi_listing.dig("info", "project_urls", "Homepage") ||
          pypi_listing.dig("info", "project_urls", "homepage") ||
          super
      end

      sig { override.returns(T.nilable(String)) }
      def attestation_changes
        return unless dependency.previous_version
        return unless dependency.version
        return if using_private_index?

        previous_attested = version_has_attestation?(dependency.previous_version)
        current_attested = version_has_attestation?(dependency.version)

        return unless previous_attested && !current_attested

        "This version has no provenance attestation, while the previous version " \
          "(#{dependency.previous_version}) was attested. Review the " \
          "[package versions](https://pypi.org/project/#{normalised_dependency_name}/#history) " \
          "before updating."
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        potential_source_urls = [
          pypi_listing.dig("info", "project_urls", "Source"),
          pypi_listing.dig("info", "project_urls", "Repository"),
          pypi_listing.dig("info", "home_page"),
          pypi_listing.dig("info", "download_url"),
          pypi_listing.dig("info", "docs_url")
        ].compact

        potential_source_urls +=
          (pypi_listing.dig("info", "project_urls") || {}).values

        source_url = potential_source_urls.find { |url| Source.from_url(url) }
        source_url ||= source_from_description
        source_url ||= source_from_homepage

        Source.from_url(source_url)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T.nilable(String)) }
      def source_from_description
        potential_source_urls = []
        desc = pypi_listing.dig("info", "description")
        return unless desc

        desc.scan(Source::SOURCE_REGEX) do
          potential_source_urls << Regexp.last_match.to_s
        end

        # Looking for a source where the repo name exactly matches the
        # dependency name
        match_url = potential_source_urls.find do |url|
          repo = Source.from_url(url)&.repo
          repo&.downcase&.end_with?(normalised_dependency_name)
        end

        return match_url if match_url

        # Failing that, look for a source where the full dependency name is
        # mentioned when the link is followed
        @source_from_description ||= T.let(
          potential_source_urls.find do |url|
            full_url = Source.from_url(url)&.url
            next unless full_url

            response = Dependabot::RegistryClient.get(url: full_url)
            next unless response.status == 200

            response.body.include?(normalised_dependency_name)
          end,
          T.nilable(String)
        )
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # rubocop:disable Metrics/PerceivedComplexity
      sig { returns(T.nilable(String)) }
      def source_from_homepage
        homepage_body_local = homepage_body
        return unless homepage_body_local

        potential_source_urls = []
        homepage_body_local.scan(Source::SOURCE_REGEX) do
          potential_source_urls << Regexp.last_match.to_s
        end

        match_url = potential_source_urls.find do |url|
          repo = Source.from_url(url)&.repo
          repo&.downcase&.end_with?(normalised_dependency_name)
        end

        return match_url if match_url

        @source_from_homepage ||= T.let(
          potential_source_urls.find do |url|
            full_url = Source.from_url(url)&.url
            next unless full_url

            response = Dependabot::RegistryClient.get(url: full_url)
            next unless response.status == 200

            response.body.include?(normalised_dependency_name)
          end,
          T.nilable(String)
        )
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { returns(T.nilable(String)) }
      def homepage_body
        homepage_url = pypi_listing.dig("info", "home_page")

        return unless homepage_url
        return if [
          "pypi.org",
          "pypi.python.org"
        ].include?(URI(homepage_url).host)

        @homepage_response ||= T.let(
          begin
            Dependabot::RegistryClient.get(url: homepage_url)
          rescue Excon::Error::Timeout, Excon::Error::Socket,
                 Excon::Error::TooManyRedirects, ArgumentError
            nil
          end,
          T.nilable(Excon::Response)
        )

        return unless @homepage_response&.status == 200

        @homepage_response&.body
      end

      sig { params(version: T.nilable(String)).returns(T::Boolean) }
      def version_has_attestation?(version)
        return false unless version

        filename = sdist_filename_for_version(version)
        return false unless filename

        url = "#{PYPI_INTEGRITY_URL}/#{normalised_dependency_name}/#{version}/#{filename}/provenance"
        response = Dependabot::RegistryClient.get(url: url)
        return false unless response.status == 200

        data = JSON.parse(response.body)
        data.is_a?(Hash) && data["attestation_bundles"].is_a?(Array) && !data["attestation_bundles"].empty?
      rescue JSON::ParserError, Excon::Error::Timeout
        false
      end

      sig { params(version: String).returns(T.nilable(String)) }
      def sdist_filename_for_version(version)
        listing = pypi_version_listing(version)
        urls = listing["urls"]
        return unless urls.is_a?(Array)

        sdist_entry = urls.find { |entry| entry["packagetype"] == "sdist" }
        sdist_entry&.fetch("filename", nil)
      end

      sig { params(version: String).returns(T::Hash[String, T.untyped]) }
      def pypi_version_listing(version)
        return T.must(@pypi_version_listings[version]) if @pypi_version_listings.key?(version)

        url = "#{MAIN_PYPI_URL}/#{normalised_dependency_name}/#{version}/json"
        response = Dependabot::RegistryClient.get(url: url)
        @pypi_version_listings[version] = response.status == 200 ? JSON.parse(response.body) : {}
      rescue JSON::ParserError, Excon::Error::Timeout
        @pypi_version_listings[version] = {}
      end

      sig { returns(T::Boolean) }
      def using_private_index?
        credentials.any? { |cred| cred["type"] == "python_index" && cred.replaces_base? }
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def pypi_listing
        return @pypi_listing unless @pypi_listing.nil?
        return @pypi_listing = {} if dependency.version&.include?("+")

        possible_listing_urls.each do |url|
          response = fetch_authed_url(url)
          next unless response.status == 200

          @pypi_listing = JSON.parse(response.body)
          return @pypi_listing
        rescue JSON::ParserError
          next
        rescue Excon::Error::Timeout
          next
        end

        @pypi_listing = {} # No listing found
      end

      sig { params(url: String).returns(Excon::Response) }
      def fetch_authed_url(url)
        if url.match(%r{(.*)://(.*?):(.*)@([^@]+)$}) &&
           Regexp.last_match&.captures&.[](1)&.include?("@")
          protocol, user, pass, url = T.must(Regexp.last_match).captures

          Dependabot::RegistryClient.get(
            url: "#{protocol}://#{url}",
            options: {
              user: user,
              password: pass
            }
          )
        else
          Dependabot::RegistryClient.get(url: url)
        end
      end

      sig { returns(T::Array[String]) }
      def possible_listing_urls
        credential_urls =
          credentials
          .select { |cred| cred["type"] == "python_index" }
          .map { |c| AuthedUrlBuilder.authed_url(credential: c) }

        (credential_urls + [MAIN_PYPI_URL]).map do |base_url|
          # Convert /simple/ endpoints to /pypi/ for JSON API access
          json_base_url = base_url.sub(%r{/simple/?$}i, "/pypi")
          json_base_url.gsub(%r{/$}, "") + "/#{normalised_dependency_name}/json"
        end
      end

      # Strip [extras] from name (dependency_name[extra_dep,other_extra])
      sig { returns(String) }
      def normalised_dependency_name
        NameNormaliser.normalise(dependency.name)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pip", Dependabot::Python::MetadataFinder)
