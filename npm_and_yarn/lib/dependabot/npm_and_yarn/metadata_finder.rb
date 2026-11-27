# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/package/npm_registry_metadata"
require "dependabot/registry_client"
require "dependabot/npm_and_yarn/package/registry_finder"
require "dependabot/npm_and_yarn/package/registry_credential_helpers"
require "dependabot/npm_and_yarn/version"

module Dependabot
  module NpmAndYarn
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig
      include Package::RegistryCredentialHelpers

      RegistryMetadata = Dependabot::Package::NpmRegistryMetadata

      # Lifecycle scripts that run automatically during package installation.
      # These are security-relevant because they execute with user privileges.
      # https://docs.npmjs.com/cli/v11/using-npm/scripts#npm-install
      INSTALL_SCRIPTS = %w(preinstall install postinstall prepublish preprepare prepare postprepare).freeze

      # RFC 3986 unreserved ASCII characters; everything else needs percent-encoding.
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

      sig { override.returns(T.nilable(String)) }
      def attestation_changes
        return unless dependency.previous_version
        return if non_standard_registry?

        previous_attested = version_has_attestation?(dependency.previous_version)
        current_attested = version_has_attestation?(dependency.version)

        return unless previous_attested && !current_attested

        "This version has no provenance attestation, while the previous version " \
          "(#{dependency.previous_version}) was attested. Review the " \
          "[package versions](https://www.npmjs.com/package/#{dependency.name}?activeTab=versions) " \
          "before updating."
      end

      sig { override.returns(T.nilable(String)) }
      def install_script_changes
        return unless dependency.previous_version

        previous_scripts = install_scripts_for_version(dependency.previous_version)
        current_scripts = install_scripts_for_version(dependency.version)

        added = current_scripts.added_since(previous_scripts)
        modified = current_scripts.modified_since(previous_scripts)
        changes = []
        changes << format_script_list("adds", added) if added.any?
        changes << format_script_list("modifies", modified) if modified.any?

        return if changes.empty?

        total_scripts = added.size + modified.size
        verb = total_scripts == 1 ? "runs" : "run"

        "This version #{changes.join(' and ')} that #{verb} during installation. " \
          "Review the package contents before updating."
      end

      private

      sig { params(action: String, scripts: T::Array[String]).returns(String) }
      def format_script_list(action, scripts)
        script_names = scripts.map { |s| "`#{s}`" }.join(", ")
        noun = scripts.size == 1 ? "script" : "scripts"
        "#{action} #{script_names} #{noun}"
      end

      # Percent-encodes npm releaser names for safe inclusion in npmjs.com profile URLs.
      sig { params(releaser: String).returns(String) }
      def encode_npm_releaser(releaser)
        return releaser unless releaser.match?(CHARS_REQUIRING_ENCODING)

        releaser.gsub(CHARS_REQUIRING_ENCODING) do |char|
          char.bytes.map { |byte| "%#{format('%02X', byte)}" }.join
        end
      end

      sig { params(version: T.nilable(String)).returns(RegistryMetadata::LifecycleScripts) }
      def install_scripts_for_version(version)
        listing = version_listing(version)
        return RegistryMetadata::LifecycleScripts.new unless listing

        listing.lifecycle_scripts(INSTALL_SCRIPTS)
      end

      sig { params(version: T.nilable(String)).returns(T::Boolean) }
      def version_has_attestation?(version)
        version_listing(version)&.attested? || false
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

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_registry
        # Attempt to use the latest version listing first, as fetching the
        # entire listing array can be slow (if it's large)
        latest_source = source_from_listing(latest_version_listing)
        return latest_source if latest_source

        seen_urls = T.let(Set.new, T::Set[String])
        all_version_listings.each do |release|
          listing_source = source_from_listing(release.listing, seen_urls)
          return listing_source if listing_source
        end

        nil
      end

      sig do
        params(
          listing: RegistryMetadata::Listing,
          seen_urls: T.nilable(T::Set[String])
        ).returns(T.nilable(Dependabot::Source))
      end
      def source_from_listing(listing, seen_urls = nil)
        listing.each_source_link do |link|
          next if seen_urls && !seen_urls.add?(link.url)

          source = link.to_source
          return source if source
        end

        nil
      end

      sig { returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash)) }
      def new_source
        sources = dependency.requirements
                            .map(&:source_hash).uniq.compact
                            .sort_by { |source| Package::RegistryFinder.central_registry?(T.cast(source[:url], String)) ? 1 : 0 }

        sources.first
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        url = new_source&.[](:url) || new_source&.fetch("url")
        Source.from_url(T.cast(url, T.nilable(String)))
      end

      sig { returns(RegistryMetadata::Listing) }
      def latest_version_listing
        return @latest_version_listing if defined?(@latest_version_listing) && @latest_version_listing

        @latest_version_listing = T.let(RegistryMetadata::Listing.new, T.nilable(RegistryMetadata::Listing))

        response = Dependabot::RegistryClient.get(url: "#{dependency_url}/latest", headers: registry_auth_headers)
        @latest_version_listing = RegistryMetadata.latest_from_json(response.body) if response.status == 200

        T.must(@latest_version_listing)
      rescue JSON::ParserError, Excon::Error::Timeout
        T.must(@latest_version_listing)
      end

      sig { params(version: T.nilable(String)).returns(T.nilable(RegistryMetadata::Listing)) }
      def version_listing(version)
        return unless version

        all_version_listings.find { |release| release.version == version }&.listing
      end

      sig { returns(T::Array[RegistryMetadata::VersionListing]) }
      def all_version_listings
        npm_listing.version_listings.sort_by { |release| NpmAndYarn::Version.new(release.version) }.reverse
      end

      sig { returns(RegistryMetadata) }
      def npm_listing
        return @npm_listing if defined?(@npm_listing) && @npm_listing

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
          if (configured_registry = configured_registry_from_credentials)
            # Prioritize replaces-base credential over lockfile source
            configured_registry
          elsif new_source.nil?
            "https://registry.npmjs.org"
          else
            new_source&.fetch(:url)
          end

        # Remove trailing slashes and escape spaces for proper URL formatting
        registry_url = URI::DEFAULT_PARSER.escape(registry_url)&.gsub(%r{/+$}, "")

        # NPM registries expect slashes to be escaped
        escaped_dependency_name = dependency.name.gsub("/", "%2F")
        "#{registry_url}/#{escaped_dependency_name}"
      end

      sig { returns(T::Hash[String, String]) }
      def registry_auth_headers
        token = auth_token
        return {} unless token

        auth_header_for(token)
      end

      sig { returns(String) }
      def dependency_registry
        # Prioritize replaces-base credential over lockfile source
        if (configured_registry = configured_registry_from_credentials)
          return configured_registry.sub(%r{^https?://}, "")
        end

        source = new_source
        return "registry.npmjs.org" if source.nil?

        T.cast(source.fetch(:url), String).gsub("https://", "").gsub("http://", "")
      end

      sig { returns(T.nilable(String)) }
      def auth_token
        credentials
          .select { |cred| cred["type"] == "npm_registry" }
          .find { |cred| cred["registry"]&.sub(%r{^https?://}, "")&.gsub(%r{/+$}, "") == dependency_registry }
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
  .register("npm_and_yarn", Dependabot::NpmAndYarn::MetadataFinder)
