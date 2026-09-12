# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/composer/version"
require "dependabot/composer/package_manager"

module Dependabot
  module Composer
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      sig do
        override
          .params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            dependency_files: T::Array[Dependabot::DependencyFile]
          )
          .void
      end
      def initialize(dependency:, credentials:, dependency_files: [])
        @packagist_listing = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        super
      end

      private

      sig { override.returns(T.nilable(Source)) }
      def look_up_source
        # The updated composer.lock (when available) was just resolved against the
        # registry, so its "source" entry for this package is the freshest, most
        # authoritative signal we have - prefer it over the dependency's embedded
        # source, which may have been carried over unchanged from before the update.
        source_from_updated_lockfile || source_from_embedded_or_packagist
      end

      sig { returns(T.nilable(Source)) }
      def source_from_embedded_or_packagist
        embedded_source = source_from_dependency
        return look_up_source_from_packagist if embedded_source.nil?
        return embedded_source unless stale_embedded_source?(embedded_source)

        # The embedded source is only known to be stale once it redirects elsewhere
        # (e.g. the package's GitHub org was renamed), so it's safe to consult
        # Packagist at this point for its current canonical location. This avoids
        # ever sending a private/custom-registry package's name to the public
        # Packagist API while its embedded source is still usable.
        look_up_source_from_packagist || embedded_source
      end

      sig { returns(T.nilable(Source)) }
      def source_from_dependency
        Source.from_url(dependency.source_string("url"))
      end

      sig { returns(T.nilable(Source)) }
      def source_from_updated_lockfile
        package_details = updated_lockfile_package_details
        return nil unless package_details

        Source.from_url(package_details.dig("source", "url"))
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def updated_lockfile_package_details
        return nil unless updated_lockfile_details

        %w(packages packages-dev).each do |key|
          entries = T.cast(updated_lockfile_details&.fetch(key, []), T::Array[T::Hash[String, T.untyped]])
          package = entries.find { |p| p["name"]&.to_s&.downcase == dependency.name.downcase }
          return package if package
        end
        nil
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def updated_lockfile_details
        return @updated_lockfile_details if defined?(@updated_lockfile_details)

        lockfile = dependency_files.find { |f| f.name == PackageManager::LOCKFILE_FILENAME }
        content = lockfile&.content

        @updated_lockfile_details = T.let(
          content.nil? ? nil : JSON.parse(content),
          T.nilable(T::Hash[String, T.untyped])
        )
      rescue JSON::ParserError
        @updated_lockfile_details = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
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
