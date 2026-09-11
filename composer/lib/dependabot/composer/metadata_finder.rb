# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/composer/version"

module Dependabot
  module Composer
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig do
        override
          .params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          )
          .void
      end
      def initialize(dependency:, credentials:)
        @packagist_listing = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        super
      end

      private

      sig { override.returns(T.nilable(Source)) }
      def look_up_source
        embedded_source = source_from_dependency
        packagist_source = look_up_source_from_packagist

        return packagist_source if embedded_source.nil?
        return embedded_source if packagist_source.nil?
        return embedded_source if embedded_source.url == packagist_source.url

        # Packagist disagrees with the dependency's embedded source (e.g. a
        # private/custom-registry package can coincidentally share a name with an
        # unrelated public Packagist package). Only trust Packagist's answer once
        # the embedded source itself confirms it's stale by redirecting elsewhere,
        # so we never silently override a still-valid private source.
        stale_embedded_source?(embedded_source) ? packagist_source : embedded_source
      end

      sig { returns(T.nilable(Source)) }
      def source_from_dependency
        Source.from_url(dependency.source_string("url"))
      end

      sig { params(source: Source).returns(T::Boolean) }
      def stale_embedded_source?(source)
        response = Dependabot::RegistryClient.head(
          url: source.url,
          options: { middlewares: Dependabot::SharedHelpers.excon_middleware - [Excon::Middleware::RedirectFollower] }
        )
        [301, 302, 303, 307, 308].include?(response.status)
      rescue Excon::Error::Timeout, Excon::Error::Socket, Excon::Error::HTTP
        false
      end

      sig { returns(T.nilable(Source)) }
      def look_up_source_from_packagist
        listing = packagist_listing
        return nil if listing&.fetch("packages", nil) == []

        packages = listing&.dig("packages", dependency.name.downcase)
        return nil unless packages

        # Packagist returns an array of version listings sorted newest to oldest.
        # So iterate until we find the first URL that appears to be a source URL.
        #
        # NOTE: Each listing may not have all fields because they are minified to remove duplicate elements:
        # * https://github.com/composer/composer/blob/main/UPGRADE-2.0.md#for-composer-repository-implementors
        # * https://github.com/composer/metadata-minifier
        packages.each do |i|
          [i.dig("source", "url"), i["homepage"]].each do |url|
            source_url = Source.from_url(url)
            return source_url unless source_url.nil?
          end
        end
        nil
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def packagist_listing
        return @packagist_listing unless @packagist_listing.nil?

        response = begin
          Dependabot::RegistryClient.get(url: "https://repo.packagist.org/p2/#{dependency.name.downcase}.json")
        rescue Excon::Error::Timeout, Excon::Error::Socket
          return nil
        end

        return nil unless response.status == 200

        @packagist_listing = JSON.parse(response.body)
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("composer", Dependabot::Composer::MetadataFinder)
