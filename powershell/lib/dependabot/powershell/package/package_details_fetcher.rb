# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/powershell"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Powershell
    module Package
      # Fetches the full set of published versions for a PowerShell module from
      # Microsoft's trusted artifact registry, falling back to the PowerShell
      # Gallery when the module is not published there.
      class PackageDetailsFetcher
        extend T::Sig

        class InvalidMarResponse < StandardError; end
        class InvalidMarPagination < InvalidMarResponse; end

        MAR_HOST = "mcr.microsoft.com"
        PSGALLERY_API_BASE = "https://www.powershellgallery.com/api/v2"
        MAR_API_BASE = "https://mcr.microsoft.com"
        MAR_REPOSITORY_PREFIX = "psresource/"
        MAR_OPEN_TIMEOUT_IN_SECONDS = 2
        MAR_READ_TIMEOUT_IN_SECONDS = 60
        MAR_SOURCE = T.let(
          { type: "registry", url: MAR_API_BASE }.freeze,
          T::Hash[Symbol, String]
        )
        PSGALLERY_SOURCE = T.let(
          { type: "registry", url: PSGALLERY_API_BASE }.freeze,
          T::Hash[Symbol, String]
        )

        # Defends against pathological or looping registry pagination.
        MAX_PAGES = 25

        UNLISTED_PUBLISHED_DATE = "1900-01-01T00:00:00"
        PSGALLERY_WEB_BASE = "https://www.powershellgallery.com"
        MANIFEST_GUID_PATTERN = /
          ['"]?GUID['"]?\s*\\?=\s*['"]
          (?<guid>[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})
          ['"]
        /ix
        GUID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

        require_relative "package_details_fetcher/mar_registry"
        require_relative "package_details_fetcher/mar_fetcher"
        require_relative "package_details_fetcher/powershell_gallery_fetcher"

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
          @registry_source = T.let(nil, T.nilable(Symbol))
          @mar_fetcher = T.let(nil, T.nilable(MarFetcher))
          @powershell_gallery_fetcher = T.let(nil, T.nilable(PowershellGalleryFetcher))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Boolean) }
        def mar_source?
          @registry_source == :mar
        end

        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def selected_source
          return MAR_SOURCE if @registry_source == :mar
          return PSGALLERY_SOURCE if @registry_source == :psgallery

          nil
        end

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: fetch_package_releases
          )
        end

        sig { params(version: String).returns(String) }
        def manifest_guid_for(version)
          return mar_fetcher.manifest_guid_for(version) if @registry_source == :mar

          powershell_gallery_fetcher.manifest_guid_for(version)
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_package_releases
          mar_releases = mar_fetcher.fetch_releases
          unless mar_releases.nil?
            @registry_source = :mar
            return mar_releases
          end

          Dependabot.logger.info(
            "#{dependency.name} is not available from Microsoft Artifact Registry; " \
            "falling back to PowerShell Gallery"
          )
          @registry_source = :psgallery
          powershell_gallery_fetcher.fetch_releases
        end

        private

        sig { returns(MarFetcher) }
        def mar_fetcher
          @mar_fetcher ||= MarFetcher.new(dependency:, max_pages: MAX_PAGES)
        end

        sig { returns(PowershellGalleryFetcher) }
        def powershell_gallery_fetcher
          @powershell_gallery_fetcher ||= PowershellGalleryFetcher.new(dependency:, max_pages: MAX_PAGES)
        end
      end
    end
  end
end
