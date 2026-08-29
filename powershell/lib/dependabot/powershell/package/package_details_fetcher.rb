# typed: strong
# frozen_string_literal: true

require "cgi"
require "json"
require "time"
require "docker_registry2"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/registry_client"
require "dependabot/powershell"
require "dependabot/powershell/version"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Powershell
    module Package
      # Fetches the full set of published versions for a PowerShell module from
      # Microsoft's trusted artifact registry, falling back to the PowerShell
      # Gallery when the module is not published there.
      #
      # The gallery exposes a NuGet v2 (OData/Atom) feed. `FindPackagesById()`
      # returns every version ever published for a module name, paginated via
      # `<link rel="next">` entries, so we must page through the whole feed
      # (up to a safety cap) to make a robust, client-side latest-version
      # selection rather than trusting the feed's `IsLatestVersion` /
      # `IsAbsoluteLatestVersion` flags (which reflect only the gallery's own
      # notion of "latest", not what Dependabot's ignore/cooldown rules allow).
      class PackageDetailsFetcher
        extend T::Sig

        PSGALLERY_API_BASE = "https://www.powershellgallery.com/api/v2"
        MAR_API_BASE = "https://mcr.microsoft.com"
        MAR_REPOSITORY_PREFIX = "psresource/"
        MAR_OPEN_TIMEOUT_IN_SECONDS = 2
        MAR_READ_TIMEOUT_IN_SECONDS = 60

        # Defends against pathological/looping feeds. In practice even the
        # most prolific PowerShell Gallery modules have far fewer than this
        # many published versions.
        MAX_PAGES = 25

        # The gallery uses a sentinel `Published` date of 1900-01-01 to mark
        # package versions that have been unlisted (delisted) by their owner,
        # following the same convention as the NuGet gallery it is built on.
        UNLISTED_PUBLISHED_DATE = "1900-01-01T00:00:00"
        PSGALLERY_WEB_BASE = "https://www.powershellgallery.com"
        MANIFEST_GUID_PATTERN = /
          ['"]?GUID['"]?\s*\\?=\s*['"]
          (?<guid>[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})
          ['"]
        /ix
        GUID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
          @registry_source = T.let(nil, T.nilable(Symbol))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: fetch_package_releases
          )
        end

        sig { params(version: String).returns(T.nilable(String)) }
        def manifest_guid_for(version)
          return mar_manifest_guid_for(version) if @registry_source == :mar

          psgallery_manifest_guid_for(version)
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_package_releases
          mar_releases = fetch_mar_package_releases
          unless mar_releases.nil?
            @registry_source = :mar
            return mar_releases
          end

          @registry_source = :psgallery
          fetch_psgallery_package_releases
        end

        private

        sig { params(version: String).returns(T.nilable(String)) }
        def psgallery_manifest_guid_for(version)
          response = Dependabot::RegistryClient.get(url: module_manifest_url(version))
          return unless response.status == 200

          manifest = Nokogiri::HTML(response.body).text.tr("\u00a0", " ")
          MANIFEST_GUID_PATTERN.match(manifest)&.[](:guid)
        rescue StandardError => e
          Dependabot.logger.error(
            "Error while fetching PowerShell Gallery manifest for #{dependency.name} #{version}: #{e.message}"
          )
          nil
        end

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def fetch_mar_package_releases
          Dependabot.logger.info("Fetching package (Microsoft Artifact Registry) info for #{dependency.name}")
          response = docker_registry_client.tags(mar_repository_name, auto_paginate: true)
          unless response.is_a?(Hash)
            Dependabot.logger.error(
              "Microsoft Artifact Registry returned an invalid response for #{dependency.name}"
            )
            return []
          end

          tags = response["tags"]

          if tags.nil?
            Dependabot.logger.error(
              "Microsoft Artifact Registry returned no tags collection for #{dependency.name}"
            )
            return []
          end

          unless tags.is_a?(Array)
            Dependabot.logger.error(
              "Microsoft Artifact Registry returned an invalid tags collection for #{dependency.name}"
            )
            return []
          end

          tags.filter_map do |tag|
            next unless tag.is_a?(String)
            next unless Powershell::Version.correct?(tag)

            Dependabot::Package::PackageRelease.new(
              version: Powershell::Version.new(tag),
              released_at: nil,
              yanked: false,
              package_type: "powershell",
              tag: tag,
              details: { "registry" => "mar" }
            )
          end
        rescue DockerRegistry2::NotFound
          Dependabot.logger.info(
            "#{dependency.name} is not available from Microsoft Artifact Registry; falling back to PowerShell Gallery"
          )
          nil
        rescue DockerRegistry2::Exception, JSON::ParserError => e
          Dependabot.logger.error(
            "Microsoft Artifact Registry lookup failed for #{dependency.name}; " \
            "PowerShell Gallery fallback is disabled for this failure: #{e.message}"
          )
          []
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_psgallery_package_releases
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])

          begin
            Dependabot.logger.info("Fetching package (PowerShell Gallery) info for #{dependency.name}")

            url = T.let(find_packages_by_id_url, T.nilable(String))
            pages = 0

            while url && pages < MAX_PAGES
              response = Dependabot::RegistryClient.get(url: url)

              # A registry failure partway through pagination means the feed
              # is incomplete - selecting a "latest" version from whatever
              # pages happened to succeed could pick an outdated version, so
              # the whole fetch is treated as failed rather than returning a
              # partial release list.
              unless response.status == 200
                Dependabot.logger.error(
                  "PowerShell Gallery returned HTTP #{response.status} while paging package info for " \
                  "#{dependency.name}; discarding partial results"
                )
                return []
              end

              document = Nokogiri::XML(response.body)
              document.remove_namespaces!

              document.css("entry").each do |entry|
                release = build_release(entry)
                releases << release if release
              end

              url = next_page_url(document)
              pages += 1
            end

            if url && pages >= MAX_PAGES
              Dependabot.logger.error(
                "PowerShell Gallery feed for #{dependency.name} exceeded the #{MAX_PAGES}-page limit; " \
                "discarding partial results"
              )
              return []
            end

            releases
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for powershell packages: #{e.message}")
            []
          end
        end

        sig { params(version: String).returns(T.nilable(String)) }
        def mar_manifest_guid_for(version)
          manifest = docker_registry_client.manifest(mar_repository_name, version)
          layers = manifest["layers"]
          return unless layers.is_a?(Array)

          layer = layers.first
          return unless layer.is_a?(Hash)

          annotations = layer["annotations"]
          return unless annotations.is_a?(Hash)

          metadata_json = annotations["metadata"]
          return unless metadata_json.is_a?(String)

          metadata = JSON.parse(metadata_json)
          return unless metadata.is_a?(Hash)

          guid = metadata["GUID"]
          guid if guid.is_a?(String) && guid.match?(GUID_PATTERN)
        rescue DockerRegistry2::Exception, JSON::ParserError => e
          Dependabot.logger.error(
            "Error while fetching Microsoft Artifact Registry manifest for " \
            "#{dependency.name} #{version}: #{e.message}"
          )
          nil
        end

        sig { returns(String) }
        def mar_repository_name
          "#{MAR_REPOSITORY_PREFIX}#{dependency.name.downcase}"
        end

        sig { returns(DockerRegistry2::Registry) }
        def docker_registry_client
          @docker_registry_client ||= T.let(
            DockerRegistry2::Registry.new(
              MAR_API_BASE,
              user: nil,
              password: nil,
              open_timeout: MAR_OPEN_TIMEOUT_IN_SECONDS,
              read_timeout: MAR_READ_TIMEOUT_IN_SECONDS,
              http_options: { proxy: ENV.fetch("HTTPS_PROXY", nil) }
            ),
            T.nilable(DockerRegistry2::Registry)
          )
        end

        sig { returns(String) }
        def find_packages_by_id_url
          escaped_id = CGI.escape("'#{dependency.name}'")
          "#{PSGALLERY_API_BASE}/FindPackagesById()?id=#{escaped_id}"
        end

        sig { params(version: String).returns(String) }
        def module_manifest_url(version)
          module_name = CGI.escape(dependency.name)
          "#{PSGALLERY_WEB_BASE}/packages/#{module_name}/#{CGI.escape(version)}/Content/#{module_name}.psd1"
        end

        sig { params(document: Nokogiri::XML::Document).returns(T.nilable(String)) }
        def next_page_url(document)
          next_link = document.at_css("feed > link[rel='next']") || document.at_css("link[rel='next']")
          href = next_link&.attribute("href")&.value
          href && !href.empty? ? href : nil
        end

        sig { params(entry: Nokogiri::XML::Element).returns(T.nilable(Dependabot::Package::PackageRelease)) }
        def build_release(entry)
          version_string = entry.at_css("properties > Version")&.text
          return nil if version_string.nil? || version_string.empty?
          return nil unless Powershell::Version.correct?(version_string)

          published = entry.at_css("properties > Published")&.text
          content_url = entry.at_css("content")&.attribute("src")&.value

          Dependabot::Package::PackageRelease.new(
            version: Powershell::Version.new(version_string),
            released_at: parse_published_time(published),
            yanked: unlisted?(published),
            url: content_url
          )
        rescue StandardError => e
          Dependabot.logger.error("Error while parsing a PowerShell Gallery feed entry: #{e.message}")
          nil
        end

        sig { params(published: T.nilable(String)).returns(T::Boolean) }
        def unlisted?(published)
          return false if published.nil? || published.empty?

          published.start_with?(UNLISTED_PUBLISHED_DATE)
        end

        sig { params(published: T.nilable(String)).returns(T.nilable(Time)) }
        def parse_published_time(published)
          return nil if published.nil? || published.empty?
          return nil if unlisted?(published)

          Time.parse(published)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
