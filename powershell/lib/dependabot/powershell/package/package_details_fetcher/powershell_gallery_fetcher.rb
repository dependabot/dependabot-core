# typed: strict
# frozen_string_literal: true

require "cgi"
require "time"
require "uri"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/registry_client"
require "dependabot/powershell/package/package_details_fetcher"
require "dependabot/powershell/version"
require "dependabot/package/package_release"

module Dependabot
  module Powershell
    module Package
      class PackageDetailsFetcher
        # The gallery exposes a NuGet v2 OData feed. FindPackagesById returns
        # every published version and paginates through Atom next links.
        class PowershellGalleryFetcher
          extend T::Sig

          API_BASE = PSGALLERY_API_BASE
          WEB_BASE = PSGALLERY_WEB_BASE
          SOURCE = PSGALLERY_SOURCE

          sig { params(dependency: Dependabot::Dependency, max_pages: Integer).void }
          def initialize(dependency:, max_pages:)
            @dependency = dependency
            @max_pages = max_pages
            @releases = T.let(nil, T.nilable(T::Array[Dependabot::Package::PackageRelease]))
            @project_urls = T.let({}, T::Hash[String, String])
          end

          sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
          def fetch_releases
            return @releases if @releases

            releases = T.let([], T::Array[Dependabot::Package::PackageRelease])
            Dependabot.logger.info("Fetching package (PowerShell Gallery) info for #{dependency.name}")

            url = T.let(find_packages_by_id_url, T.nilable(String))
            visited_urls = T.let({}, T::Hash[String, T::Boolean])
            pages = 0

            while url
              current_url = prepare_page_url(url, visited_urls, pages)
              response = fetch_page(current_url)
              document = parse_page(response.body)

              document.css("entry").each do |entry|
                release = build_release(entry)
                releases << release if release
              end

              url = next_page_url(document)
              pages += 1
            end

            @releases = releases
          end

          sig { params(version: String).returns(String) }
          def manifest_guid_for(version)
            response = fetch_page(module_manifest_url(version))

            manifest = Nokogiri::HTML(response.body).text.tr("\u00a0", " ")
            guid = MANIFEST_GUID_PATTERN.match(manifest)&.[](:guid)
            return guid if guid

            raise Dependabot::DependencyFileNotResolvable,
                  "PowerShell Gallery manifest for #{dependency.name} #{version} did not contain a valid GUID"
          end

          sig { params(version: String).returns(T.nilable(String)) }
          def project_url_for(version)
            fetch_releases
            @project_urls[version]
          end

          private

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig do
            params(
              next_url: String,
              visited_urls: T::Hash[String, T::Boolean],
              pages: Integer
            ).returns(String)
          end
          def prepare_page_url(next_url, visited_urls, pages)
            page_limit_error = "PowerShell Gallery feed for #{dependency.name} exceeded the #{@max_pages}-page limit"
            raise Dependabot::DependencyFileNotResolvable, page_limit_error if pages >= @max_pages

            current_url = URI.join("#{API_BASE}/", next_url).to_s
            uri = URI(current_url)
            invalid_url_error = "PowerShell Gallery response for #{dependency.name} contained an invalid pagination URL"
            valid_uri = uri.scheme == "https" && uri.host == URI(API_BASE).host
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
          def fetch_page(url)
            response = Dependabot::RegistryClient.get(url:)
            return response if response.status == 200

            message = "PowerShell Gallery returned HTTP #{response.status} while fetching #{dependency.name}"
            raise Dependabot::RegistryError.new(response.status, message)
          rescue Excon::Error::Timeout
            raise Dependabot::PrivateSourceTimedOut.new(API_BASE), cause: nil
          rescue Excon::Error::Certificate
            raise Dependabot::PrivateSourceCertificateFailure.new(API_BASE), cause: nil
          rescue Excon::Error::Socket
            message = "PowerShell Gallery returned a broken response while fetching #{dependency.name}"
            raise Dependabot::PrivateSourceBadResponse.new(API_BASE, message), cause: nil
          end

          sig { params(body: String).returns(Nokogiri::XML::Document) }
          def parse_page(body)
            document = Nokogiri::XML(body, &:strict)
            document.remove_namespaces!
            malformed_error = "PowerShell Gallery returned malformed XML for #{dependency.name}: " \
                              "expected a feed document"
            raise Dependabot::DependencyFileNotResolvable, malformed_error unless document.root&.name == "feed"

            document
          rescue Nokogiri::XML::SyntaxError
            message = "PowerShell Gallery returned malformed XML for #{dependency.name}"
            raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
          end

          sig { returns(String) }
          def find_packages_by_id_url
            escaped_id = CGI.escape("'#{dependency.name}'")
            "#{API_BASE}/FindPackagesById()?id=#{escaped_id}"
          end

          sig { params(version: String).returns(String) }
          def module_manifest_url(version)
            module_name = CGI.escape(dependency.name)
            "#{WEB_BASE}/packages/#{module_name}/#{CGI.escape(version)}/Content/#{module_name}.psd1"
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
            record_project_url(entry, version_string)

            Dependabot::Package::PackageRelease.new(
              version: Powershell::Version.new(version_string),
              released_at: parse_published_time(published),
              yanked: unlisted?(published),
              url: content_url
            )
          end

          sig { params(entry: Nokogiri::XML::Element, version: String).void }
          def record_project_url(entry, version)
            project_url = entry.at_css("properties > ProjectUrl")&.text
            return unless project_url&.valid_encoding?

            @project_urls[version] = project_url.dup.freeze
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
end
