# typed: strict
# frozen_string_literal: true

require "excon"
require "openssl"
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
        @parsed_source_urls = T.let({}, T::Hash[String, T.nilable(Dependabot::Source)])
      end

      sig { returns(T.nilable(String)) }
      def homepage_url
        pypi_listing.dig("info", "home_page") ||
          pypi_listing.dig("info", "project_urls", "Homepage") ||
          pypi_listing.dig("info", "project_urls", "homepage") ||
          super
      end

      sig { override.returns(T.nilable(String)) }
      def maintainer_changes
        return unless dependency.previous_version
        return unless dependency.version

        previous_ownership = ownership_for_version(T.must(dependency.previous_version))
        current_ownership = ownership_for_version(T.must(dependency.version))

        return if previous_ownership.nil? || current_ownership.nil?

        previous_org = previous_ownership["organization"]
        current_org = current_ownership["organization"]

        if previous_org != current_org && !(previous_org.nil? && current_org)
          return "The organization that maintains #{dependency.name} on PyPI has " \
                 "changed since your current version."
        end

        previous_users = ownership_users(previous_ownership)
        current_users = ownership_users(current_ownership)

        # Warn only when there were previous maintainers and none of them remain
        return unless previous_users.any? && !previous_users.intersect?(current_users)

        "None of the maintainers for your current version of #{dependency.name} are " \
          "listed as maintainers for the new version on PyPI."
      end

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        source_url = exact_match_source_url_from_project_urls
        source_url ||= labelled_source_url_from_project_urls
        source_url ||= fallback_source_url
        source_url ||= source_from_description
        source_url ||= source_from_homepage

        parsed_source_from_url(source_url)
      end

      sig { returns(T.nilable(String)) }
      def exact_match_source_url_from_project_urls
        project_urls.values.find do |url|
          repo = parsed_source_from_url(url)&.repo
          repo&.downcase&.end_with?(normalised_dependency_name)
        end
      end

      sig { returns(T.nilable(String)) }
      def labelled_source_url_from_project_urls
        source_urls = source_like_project_url_labels.filter_map do |label|
          project_urls[label]
        end

        source_urls.find { |url| parsed_source_from_url(url) }
      end

      sig { returns(T.nilable(String)) }
      def fallback_source_url
        potential_source_urls = [
          pypi_listing.dig("info", "home_page"),
          pypi_listing.dig("info", "download_url"),
          pypi_listing.dig("info", "docs_url")
        ].compact

        potential_source_urls += project_urls.values

        potential_source_urls.find { |url| parsed_source_from_url(url) }
      end

      sig { returns(T::Hash[String, String]) }
      def project_urls
        pypi_listing.dig("info", "project_urls") || {}
      end

      sig { returns(T::Array[String]) }
      def source_like_project_url_labels
        ["Source", "Source Code", "Repository", "Code", "Homepage"]
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
          repo = parsed_source_from_url(url)&.repo
          repo&.downcase&.end_with?(normalised_dependency_name)
        end

        return match_url if match_url

        # Failing that, look for a source where the full dependency name is
        # mentioned when the link is followed
        @source_from_description ||= T.let(
          potential_source_urls.find do |url|
            full_url = parsed_source_from_url(url)&.url
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
          repo = parsed_source_from_url(url)&.repo
          repo&.downcase&.end_with?(normalised_dependency_name)
        end

        return match_url if match_url

        @source_from_homepage ||= T.let(
          potential_source_urls.find do |url|
            full_url = parsed_source_from_url(url)&.url
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
                 Excon::Error::TooManyRedirects, OpenSSL::SSL::SSLError, ArgumentError => e
            Dependabot.logger.warn("Error fetching Python homepage URL #{homepage_url}: #{e.class}: #{e.message}")
            nil
          end,
          T.nilable(Excon::Response)
        )

        return unless @homepage_response&.status == 200

        @homepage_response&.body
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
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket, OpenSSL::SSL::SSLError => e
          Dependabot.logger.warn("Error fetching Python package listing from #{url}: #{e.class}: #{e.message}")
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

      sig { params(version: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def ownership_for_version(version)
        return nil if version.include?("+")

        possible_version_listing_urls(version).each do |url|
          response = fetch_authed_url(url)
          next unless response.status == 200

          data = JSON.parse(response.body)
          return data["ownership"]
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket, OpenSSL::SSL::SSLError => e
          Dependabot.logger.warn(
            "Error fetching Python package ownership from #{url} for version #{version}: #{e.class}: #{e.message}"
          )
          next
        end

        nil
      end

      sig { params(version: String).returns(T::Array[String]) }
      def possible_version_listing_urls(version)
        possible_listing_urls.map do |url|
          url.sub(%r{/json$}, "/#{URI::DEFAULT_PARSER.escape(version)}/json")
        end
      end

      sig { params(ownership: T::Hash[String, T.untyped]).returns(T::Array[String]) }
      def ownership_users(ownership)
        roles = ownership["roles"]
        return [] unless roles.is_a?(Array)

        roles.filter_map { |role| role["user"] if role.is_a?(Hash) }
      end

      # Strip [extras] from name (dependency_name[extra_dep,other_extra])
      sig { returns(String) }
      def normalised_dependency_name
        NameNormaliser.normalise(dependency.name)
      end

      sig { params(url: T.nilable(String)).returns(T.nilable(Dependabot::Source)) }
      def parsed_source_from_url(url)
        return unless url
        return @parsed_source_urls[url] if @parsed_source_urls.key?(url)

        @parsed_source_urls[url] = Source.from_url(url)
      end
    end
  end
end

Dependabot::MetadataFinders.register("pip", Dependabot::Python::MetadataFinder)
