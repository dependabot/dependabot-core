# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/package/npm_registry_metadata"
require "dependabot/registry_client"
require "dependabot/bun/package/registry_finder"
require "dependabot/bun/version"

module Dependabot
  module Bun
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      RegistryMetadata = Dependabot::Package::NpmRegistryMetadata

      # RFC 3986 unreserved; others need encoding (explicit ASCII class avoids UTF-8 \w issues)
      CHARS_REQUIRING_ENCODING = /[^A-Za-z0-9._~-]/
      private_constant :CHARS_REQUIRING_ENCODING

      sig { override.returns(T.nilable(String)) }
      def homepage_url
        # Attempt to use version_listing first, as fetching the entire listing
        # array can be slow (if it's large)
        latest_version_listing.homepage ||
          all_version_listings.lazy.filter_map { |release| release.listing.homepage }.first ||
          super
      end

      sig { override.returns(T.nilable(String)) }
      def maintainer_changes
        releaser = npm_releaser
        return unless releaser
        return unless npm_listing.published?(dependency.version)
        return if previous_releasers&.include?(releaser)

        encoded_releaser = encode_npm_releaser(releaser)
        "This version was pushed to npm by " \
          "[#{releaser}](https://www.npmjs.com/~#{encoded_releaser}), a new " \
          "releaser for #{dependency.name} since your current version."
      end

      private

      # Percent-encodes npm releaser names for safe inclusion in npmjs.com profile URLs.
      sig { params(releaser: String).returns(String) }
      def encode_npm_releaser(releaser)
        return releaser unless releaser.match?(CHARS_REQUIRING_ENCODING)

        releaser.gsub(CHARS_REQUIRING_ENCODING) do |char|
          char.bytes.map { |byte| "%#{format('%02X', byte)}" }.join
        end
      end

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return find_source_from_registry if new_source.nil?

        source_type = new_source&.[](:type) || new_source&.fetch("type")

        case source_type
        when "git" then find_source_from_git_url
        when "registry" then find_source_from_registry
        else raise "Unexpected source type: #{source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def npm_releaser
        all_version_listings
          .find { |release| release.version == dependency.version }
          &.listing&.releaser
      end

      sig { returns(T.nilable(T::Array[String])) }
      def previous_releasers
        cutoff =
          if dependency.previous_version && npm_listing.published?(dependency.previous_version)
            npm_listing.published_at(dependency.previous_version)
          elsif npm_listing.published?(dependency.version)
            npm_listing.published_at(dependency.version) - 1
          end
        return unless cutoff

        all_version_listings
          .reject { |release| npm_listing.published_at(release.version) > cutoff }
          .filter_map { |release| release.listing.historical_releaser }
      end

      sig { returns(T.nilable(Source)) }
      def find_source_from_registry
        # Attempt to use version_listing first, as fetching the entire listing
        # array can be slow (if it's large)
        potential_sources = sources_from_listing(latest_version_listing)
        return potential_sources.first if potential_sources.any?

        all_version_listings.flat_map { |release| sources_from_listing(release.listing) }.first
      end

      sig { params(listing: RegistryMetadata::Listing).returns(T::Array[Source]) }
      def sources_from_listing(listing)
        sources = T.let([], T::Array[Source])
        listing.each_source_link do |link|
          source = link.to_source
          sources << source if source
        end
        sources
      end

      sig { returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash)) }
      def new_source
        sources = dependency.requirements
                            .map(&:source_hash).uniq.compact
                            .sort_by { |source| Package::RegistryFinder.central_registry?(T.cast(source[:url], String)) ? 1 : 0 }

        sources.first
      end

      sig { returns(T.nilable(Source)) }
      def find_source_from_git_url
        url = new_source&.[](:url) || new_source&.fetch("url")
        Source.from_url(T.cast(url, T.nilable(String)))
      end

      sig { returns(RegistryMetadata::Listing) }
      def latest_version_listing
        return @latest_version_listing unless @latest_version_listing.nil?

        @latest_version_listing = T.let(RegistryMetadata::Listing.new, T.nilable(RegistryMetadata::Listing))

        response = Dependabot::RegistryClient.get(
          url: "#{dependency_url}/latest",
          headers: registry_auth_headers
        )
        return T.must(@latest_version_listing) if response.status >= 500

        begin
          # A registry can answer a missing package with a bare JSON string such as "Not Found"
          @latest_version_listing = RegistryMetadata.latest_from_json(response.body)
        rescue JSON::ParserError
          raise unless non_standard_registry?
        end

        T.must(@latest_version_listing)
      rescue JSON::ParserError, Excon::Error::Timeout
        T.must(@latest_version_listing)
      end

      sig { returns(T::Array[RegistryMetadata::VersionListing]) }
      def all_version_listings
        npm_listing.version_listings.sort_by { |release| Bun::Version.new(release.version) }.reverse
      end

      sig { returns(RegistryMetadata) }
      def npm_listing
        return @npm_listing unless @npm_listing.nil?

        @npm_listing = T.let(RegistryMetadata.new, T.nilable(RegistryMetadata))

        response = Dependabot::RegistryClient.get(url: dependency_url, headers: registry_auth_headers)
        return T.must(@npm_listing) if response.status >= 500

        begin
          @npm_listing = RegistryMetadata.from_json(response.body)
        rescue JSON::ParserError
          raise unless non_standard_registry?
        end

        T.must(@npm_listing)
      rescue Excon::Error::Timeout
        T.must(@npm_listing)
      end

      sig { returns(String) }
      def dependency_url
        registry_url =
          if new_source.nil?
            configured_registry_from_credentials || "https://registry.npmjs.org"
          else
            new_source&.fetch(:url)
          end

        # Remove trailing slashes and escape spaces for proper URL formatting
        registry_url = URI::DEFAULT_PARSER.escape(registry_url)&.gsub(%r{/+$}, "")

        # NPM registries expect slashes to be escaped
        escaped_dependency_name = dependency.name.gsub("/", "%2F")
        "#{registry_url}/#{escaped_dependency_name}"
      end

      sig { returns(T.nilable(String)) }
      def configured_registry_from_credentials
        # Look for a credential that replaces the base registry (global registry replacement)
        replaces_base_cred = credentials.find { |cred| cred["type"] == "npm_registry" && cred.replaces_base? }
        return normalize_registry_url(replaces_base_cred["registry"]) if replaces_base_cred

        nil
      end

      sig { params(registry: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_registry_url(registry)
        return nil unless registry
        return registry if registry.start_with?("http")

        "https://#{registry}"
      end

      sig { returns(T::Hash[String, String]) }
      def registry_auth_headers
        return {} unless auth_token

        { "Authorization" => "Bearer #{auth_token}" }
      end

      sig { returns(String) }
      def dependency_registry
        source = new_source
        return "registry.npmjs.org" if source.nil?

        T.cast(source.fetch(:url), String).gsub("https://", "").gsub("http://", "")
      end

      sig { returns(T.nilable(String)) }
      def auth_token
        credentials
          .select { |cred| cred["type"] == "npm_registry" }
          .find { |cred| cred["registry"] == dependency_registry }
          &.fetch("token", nil)
      end

      sig { returns(T::Boolean) }
      def non_standard_registry?
        dependency_registry != "registry.npmjs.org"
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("bun", Dependabot::Bun::MetadataFinder)
