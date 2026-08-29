# typed: strict
# frozen_string_literal: true

require "json"
require "uri"
require "docker_registry2"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/powershell/package/package_details_fetcher"
require "dependabot/powershell/version"
require "dependabot/package/package_release"

module Dependabot
  module Powershell
    module Package
      class PackageDetailsFetcher
        class MarFetcher
          extend T::Sig

          InvalidResponse = InvalidMarResponse
          InvalidPagination = InvalidMarPagination
          API_BASE = MAR_API_BASE
          REPOSITORY_PREFIX = MAR_REPOSITORY_PREFIX
          OPEN_TIMEOUT_IN_SECONDS = MAR_OPEN_TIMEOUT_IN_SECONDS
          READ_TIMEOUT_IN_SECONDS = MAR_READ_TIMEOUT_IN_SECONDS
          SOURCE = MAR_SOURCE

          sig { params(dependency: Dependabot::Dependency, max_pages: Integer).void }
          def initialize(dependency:, max_pages:)
            @dependency = dependency
            @max_pages = max_pages
          end

          sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
          def fetch_releases
            Dependabot.logger.info("Fetching package (Microsoft Artifact Registry) info for #{dependency.name}")
            tags = fetch_tags
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
            raise Dependabot::PrivateSourceAuthenticationFailure.new(API_BASE), cause: nil
          rescue DockerRegistry2::RegistryUnknownException
            raise Dependabot::PrivateSourceTimedOut.new(API_BASE), cause: nil
          rescue DockerRegistry2::RegistrySSLException
            raise Dependabot::PrivateSourceCertificateFailure.new(API_BASE), cause: nil
          rescue DockerRegistry2::RegistryHTTPException => e
            raise MarRegistry.registry_error(e, dependency.name), cause: nil
          rescue InvalidPagination
            message = "Microsoft Artifact Registry response for #{dependency.name} contained invalid pagination data"
            raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
          rescue JSON::ParserError, InvalidResponse
            message = "Microsoft Artifact Registry response for #{dependency.name} was malformed or incomplete"
            raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
          end

          sig { params(version: String).returns(String) }
          def manifest_guid_for(version)
            manifest = docker_registry_client.manifest(repository_name, version)
            metadata = MarRegistry.manifest_metadata(manifest)
            guid = metadata["GUID"] if metadata.is_a?(Hash)
            return guid if guid.is_a?(String) && guid.valid_encoding? && guid.match?(GUID_PATTERN)

            raise Dependabot::DependencyFileNotResolvable,
                  "Microsoft Artifact Registry manifest for #{dependency.name} #{version} did not contain a valid GUID"
          rescue DockerRegistry2::RegistryAuthenticationException,
                 DockerRegistry2::RegistryAuthorizationException
            raise Dependabot::PrivateSourceAuthenticationFailure.new(API_BASE), cause: nil
          rescue DockerRegistry2::RegistryUnknownException
            raise Dependabot::PrivateSourceTimedOut.new(API_BASE), cause: nil
          rescue DockerRegistry2::RegistrySSLException
            raise Dependabot::PrivateSourceCertificateFailure.new(API_BASE), cause: nil
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

          private

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(T.nilable(T::Array[String])) }
          def fetch_tags
            tags = T.let([], T::Array[String])
            next_url = T.let("v2/#{repository_name}/tags/list", T.nilable(String))
            visited_urls = T.let({}, T::Hash[String, T::Boolean])
            first_page = T.let(true, T::Boolean)
            pages = 0

            while next_url
              current_url = prepare_page_url(next_url, visited_urls, pages)
              response = fetch_tags_page(current_url, first_page:)
              return nil unless response

              tags.concat(tags_from(response))
              next_url = next_page_url(response)
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
          def prepare_page_url(next_url, visited_urls, pages)
            raise InvalidPagination if pages >= @max_pages

            current_url = URI.join("#{API_BASE}/", next_url).to_s
            raise InvalidPagination if visited_urls[current_url]

            visited_urls[current_url] = true
            current_url
          rescue URI::Error
            raise InvalidPagination, cause: nil
          end

          sig do
            params(current_url: String, first_page: T::Boolean).returns(T.nilable(DockerRegistry2::Response))
          end
          def fetch_tags_page(current_url, first_page:)
            docker_registry_client.doget(current_url)
          rescue DockerRegistry2::NotFound
            unless first_page
              message = "Microsoft Artifact Registry returned HTTP 404 for a later tags page for #{dependency.name}"
              raise Dependabot::RegistryError.new(404, message), cause: nil
            end

            nil
          end

          sig { params(response: DockerRegistry2::Response).returns(T::Array[String]) }
          def tags_from(response)
            page = JSON.parse(response.body)
            raise InvalidResponse, "Invalid tags response for #{dependency.name}" unless page.is_a?(Hash)

            page_tags = page["tags"]
            unless page_tags.is_a?(Array) &&
                   page_tags.all? { |tag| tag.is_a?(String) && tag.valid_encoding? }
              raise InvalidResponse, "Invalid tags response for #{dependency.name}"
            end

            page_tags
          end

          sig { params(response: DockerRegistry2::Response).returns(T.nilable(String)) }
          def next_page_url(response)
            link = response.headers[:link]
            return unless link
            raise InvalidPagination unless link.is_a?(String) && link.valid_encoding?

            match = link.match(/<(?<url>[^>]+)>\s*;\s*rel="?next"?/i)
            raise InvalidPagination unless match

            next_url = MarRegistry.resolve_tags_page_url(response.request_url, T.must(match[:url]), repository_name)
            raise InvalidPagination unless next_url

            next_url
          end

          sig { returns(String) }
          def repository_name
            "#{REPOSITORY_PREFIX}#{dependency.name.downcase}"
          end

          sig { returns(DockerRegistry2::Registry) }
          def docker_registry_client
            @docker_registry_client ||= T.let(
              MarRegistry.new(
                API_BASE,
                user: nil,
                password: nil,
                open_timeout: OPEN_TIMEOUT_IN_SECONDS,
                read_timeout: READ_TIMEOUT_IN_SECONDS,
                http_options: { proxy: ENV.fetch("HTTPS_PROXY", nil) }
              ),
              T.nilable(DockerRegistry2::Registry)
            )
          end
        end
      end
    end
  end
end
