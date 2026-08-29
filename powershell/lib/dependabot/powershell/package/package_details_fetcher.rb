# typed: strict
# frozen_string_literal: true

require "cgi"
require "json"
require "time"
require "uri"
require "docker_registry2"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/errors"
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

        require_relative "package_details_fetcher/mar_registry"

        class InvalidMarResponse < StandardError; end
        class InvalidMarPagination < InvalidMarResponse; end

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

        sig { params(version: String).returns(String) }
        def psgallery_manifest_guid_for(version)
          response = fetch_psgallery_page(module_manifest_url(version))

          manifest = Nokogiri::HTML(response.body).text.tr("\u00a0", " ")
          guid = MANIFEST_GUID_PATTERN.match(manifest)&.[](:guid)
          return guid if guid

          raise Dependabot::DependencyFileNotResolvable,
                "PowerShell Gallery manifest for #{dependency.name} #{version} did not contain a valid GUID"
        end

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def fetch_mar_package_releases
          Dependabot.logger.info("Fetching package (Microsoft Artifact Registry) info for #{dependency.name}")
          tags = fetch_mar_tags
          return nil unless tags

          tags.filter_map do |tag|
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
        rescue DockerRegistry2::RegistryAuthenticationException,
               DockerRegistry2::RegistryAuthorizationException
          raise Dependabot::PrivateSourceAuthenticationFailure.new(MAR_API_BASE), cause: nil
        rescue DockerRegistry2::RegistryUnknownException
          raise Dependabot::PrivateSourceTimedOut.new(MAR_API_BASE), cause: nil
        rescue DockerRegistry2::RegistrySSLException
          raise Dependabot::PrivateSourceCertificateFailure.new(MAR_API_BASE), cause: nil
        rescue DockerRegistry2::RegistryHTTPException => e
          raise MarRegistry.registry_error(e, dependency.name), cause: nil
        rescue InvalidMarPagination
          message = "Microsoft Artifact Registry response for #{dependency.name} contained invalid pagination data"
          raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
        rescue JSON::ParserError, InvalidMarResponse
          message = "Microsoft Artifact Registry response for #{dependency.name} was malformed or incomplete"
          raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
        end

        sig { returns(T.nilable(T::Array[String])) }
        def fetch_mar_tags
          tags = T.let([], T::Array[String])
          next_url = T.let("v2/#{mar_repository_name}/tags/list", T.nilable(String))
          visited_urls = T.let({}, T::Hash[String, T::Boolean])
          first_page = T.let(true, T::Boolean)
          pages = 0

          while next_url
            current_url = prepare_mar_page_url(next_url, visited_urls, pages)
            response = fetch_mar_tags_page(current_url, first_page:)
            return nil unless response

            tags.concat(mar_tags_from(response))
            next_url = mar_next_page_url(response)
            first_page = false
            pages += 1
          end

          tags.uniq
        end

        sig do
          params(
            next_url: String,
            visited_urls: T::Hash[String, T::Boolean],
            pages: Integer
          ).returns(String)
        end
        def prepare_mar_page_url(next_url, visited_urls, pages)
          raise InvalidMarPagination if pages >= MAX_PAGES

          current_url = URI.join("#{MAR_API_BASE}/", next_url).to_s
          raise InvalidMarPagination if visited_urls[current_url]

          visited_urls[current_url] = true
          current_url
        rescue URI::Error
          raise InvalidMarPagination, cause: nil
        end

        sig do
          params(current_url: String, first_page: T::Boolean).returns(T.nilable(DockerRegistry2::Response))
        end
        def fetch_mar_tags_page(current_url, first_page:)
          docker_registry_client.doget(current_url)
        rescue DockerRegistry2::NotFound
          unless first_page
            message = "Microsoft Artifact Registry returned HTTP 404 for a later tags page for #{dependency.name}"
            raise Dependabot::RegistryError.new(404, message), cause: nil
          end

          Dependabot.logger.info(
            "#{dependency.name} is not available from Microsoft Artifact Registry; " \
            "falling back to PowerShell Gallery"
          )
          nil
        end

        sig { params(response: DockerRegistry2::Response).returns(T::Array[String]) }
        def mar_tags_from(response)
          page = JSON.parse(response.body)
          raise InvalidMarResponse, "Invalid tags response for #{dependency.name}" unless page.is_a?(Hash)

          page_tags = page["tags"]
          unless page_tags.is_a?(Array) &&
                 page_tags.all? { |tag| tag.is_a?(String) && tag.valid_encoding? }
            raise InvalidMarResponse, "Invalid tags response for #{dependency.name}"
          end

          page_tags
        end

        sig { params(response: DockerRegistry2::Response).returns(T.nilable(String)) }
        def mar_next_page_url(response)
          link = response.headers[:link]
          return unless link
          raise InvalidMarPagination unless link.is_a?(String) && link.valid_encoding?

          match = link.match(/<(?<url>[^>]+)>\s*;\s*rel="?next"?/i)
          raise InvalidMarPagination unless match

          next_url = MarRegistry.resolve_tags_page_url(response.request_url, T.must(match[:url]), mar_repository_name)
          raise InvalidMarPagination unless next_url

          next_url
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_psgallery_package_releases
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])
          Dependabot.logger.info("Fetching package (PowerShell Gallery) info for #{dependency.name}")

          url = T.let(find_packages_by_id_url, T.nilable(String))
          visited_urls = T.let({}, T::Hash[String, T::Boolean])
          pages = 0

          while url
            current_url = prepare_psgallery_page_url(url, visited_urls, pages)
            response = fetch_psgallery_page(current_url)
            document = parse_psgallery_page(response.body)

            document.css("entry").each do |entry|
              release = build_release(entry)
              releases << release if release
            end

            url = next_page_url(document)
            pages += 1
          end

          releases
        end

        sig do
          params(
            next_url: String,
            visited_urls: T::Hash[String, T::Boolean],
            pages: Integer
          ).returns(String)
        end
        def prepare_psgallery_page_url(next_url, visited_urls, pages)
          page_limit_error = "PowerShell Gallery feed for #{dependency.name} exceeded the #{MAX_PAGES}-page limit"
          raise Dependabot::DependencyFileNotResolvable, page_limit_error if pages >= MAX_PAGES

          current_url = URI.join("#{PSGALLERY_API_BASE}/", next_url).to_s
          uri = URI(current_url)
          invalid_url_error = "PowerShell Gallery response for #{dependency.name} contained an invalid pagination URL"
          valid_uri = uri.scheme == "https" && uri.host == URI(PSGALLERY_API_BASE).host
          raise Dependabot::DependencyFileNotResolvable, invalid_url_error unless valid_uri

          repeated_url_error = "PowerShell Gallery response for #{dependency.name} repeated a pagination URL"
          raise Dependabot::DependencyFileNotResolvable, repeated_url_error if visited_urls[current_url]

          visited_urls[current_url] = true
          current_url
        rescue URI::Error
          message = "PowerShell Gallery response for #{dependency.name} contained an invalid pagination URL"
          raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
        end

        sig { params(url: String).returns(Excon::Response) }
        def fetch_psgallery_page(url)
          response = Dependabot::RegistryClient.get(url:)
          return response if response.status == 200

          message = "PowerShell Gallery returned HTTP #{response.status} while fetching #{dependency.name}"
          raise Dependabot::RegistryError.new(response.status, message)
        rescue Excon::Error::Timeout
          raise Dependabot::PrivateSourceTimedOut.new(PSGALLERY_API_BASE), cause: nil
        rescue Excon::Error::Certificate
          raise Dependabot::PrivateSourceCertificateFailure.new(PSGALLERY_API_BASE), cause: nil
        rescue Excon::Error::Socket
          message = "PowerShell Gallery returned a broken response while fetching #{dependency.name}"
          raise Dependabot::PrivateSourceBadResponse.new(PSGALLERY_API_BASE, message), cause: nil
        end

        sig { params(body: String).returns(Nokogiri::XML::Document) }
        def parse_psgallery_page(body)
          document = Nokogiri::XML(body, &:strict)
          document.remove_namespaces!
          malformed_error = "PowerShell Gallery returned malformed XML for #{dependency.name}: expected a feed document"
          raise Dependabot::DependencyFileNotResolvable, malformed_error unless document.root&.name == "feed"

          document
        rescue Nokogiri::XML::SyntaxError
          message = "PowerShell Gallery returned malformed XML for #{dependency.name}"
          raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
        end

        sig { params(version: String).returns(String) }
        def mar_manifest_guid_for(version)
          manifest = docker_registry_client.manifest(mar_repository_name, version)
          metadata = MarRegistry.manifest_metadata(manifest)
          guid = metadata["GUID"] if metadata.is_a?(Hash)
          return guid if guid.is_a?(String) && guid.valid_encoding? && guid.match?(GUID_PATTERN)

          raise Dependabot::DependencyFileNotResolvable,
                "Microsoft Artifact Registry manifest for #{dependency.name} #{version} did not contain a valid GUID"
        rescue DockerRegistry2::RegistryAuthenticationException,
               DockerRegistry2::RegistryAuthorizationException
          raise Dependabot::PrivateSourceAuthenticationFailure.new(MAR_API_BASE), cause: nil
        rescue DockerRegistry2::RegistryUnknownException
          raise Dependabot::PrivateSourceTimedOut.new(MAR_API_BASE), cause: nil
        rescue DockerRegistry2::RegistrySSLException
          raise Dependabot::PrivateSourceCertificateFailure.new(MAR_API_BASE), cause: nil
        rescue DockerRegistry2::NotFound
          message = "Microsoft Artifact Registry returned HTTP 404 for #{dependency.name} #{version} manifest"
          raise Dependabot::RegistryError.new(404, message), cause: nil
        rescue DockerRegistry2::RegistryHTTPException => e
          raise MarRegistry.registry_error(e, dependency.name), cause: nil
        rescue MarRegistry::InvalidManifest
          raise(
            Dependabot::DependencyFileNotResolvable.new(
              "Microsoft Artifact Registry response for #{dependency.name} #{version} contained a malformed manifest"
            ),
            cause: nil
          )
        rescue MarRegistry::InvalidMetadata
          raise(
            Dependabot::DependencyFileNotResolvable.new(
              "Microsoft Artifact Registry manifest for #{dependency.name} #{version} contained malformed metadata"
            ),
            cause: nil
          )
        end

        sig { returns(String) }
        def mar_repository_name
          "#{MAR_REPOSITORY_PREFIX}#{dependency.name.downcase}"
        end

        sig { returns(DockerRegistry2::Registry) }
        def docker_registry_client
          @docker_registry_client ||= T.let(
            MarRegistry.new(
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
          return unless next_link

          href = next_link&.attribute("href")&.value
          if href.nil? || href.empty?
            raise Dependabot::DependencyFileNotResolvable,
                  "PowerShell Gallery response for #{dependency.name} contained an invalid pagination link"
          end

          href
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
