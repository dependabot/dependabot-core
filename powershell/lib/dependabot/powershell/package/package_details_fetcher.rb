# typed: strict
# frozen_string_literal: true

require "cgi"
require "time"
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
      # the PowerShell Gallery (the only registry currently supported).
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

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
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

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_package_releases
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
              Dependabot.logger.warn(
                "Stopped paging PowerShell Gallery feed for #{dependency.name} after #{MAX_PAGES} pages"
              )
            end

            releases
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for powershell packages: #{e.message}")
            []
          end
        end

        private

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
