# typed: true
# frozen_string_literal: true

require "nokogiri"
require "zip"
require "stringio"
require "dependabot/nuget/http_response_helpers"

module Dependabot
  module Nuget
    class NupkgFetcher
      require_relative "repository_finder"

      def self.fetch_nupkg_buffer(dependency_urls, package_id, package_version)
        # check all repositories for the first one that has the nupkg
        dependency_urls.reduce(nil) do |nupkg_buffer, repository_details|
          nupkg_buffer || fetch_nupkg_buffer_from_repository(repository_details, package_id, package_version)
        end
      end

      def self.fetch_nupkg_url_from_repository(repository_details, package_id, package_version)
        return unless package_id && package_version && !package_version.empty?

        feed_url = repository_details[:repository_url]
        repository_type = repository_details[:repository_type]

        package_url = if repository_type == "v2"
                        get_nuget_v2_package_url(repository_details, package_id, package_version)
                      elsif repository_type == "v3"
                        get_nuget_v3_package_url(repository_details, package_id, package_version)
                      else
                        raise Dependabot::DependencyFileNotResolvable, "Unexpected NuGet feed format: #{feed_url}"
                      end

        package_url
      end

      def self.fetch_nupkg_buffer_from_repository(repository_details, package_id, package_version)
        package_url = fetch_nupkg_url_from_repository(repository_details, package_id, package_version)
        return unless package_url

        auth_header = repository_details[:auth_header]
        fetch_stream(package_url, auth_header)
      end

      def self.get_nuget_v3_package_url(repository_details, package_id, package_version)
        base_url = repository_details[:base_url]
        unless base_url
          return get_nuget_v3_package_url_from_search(repository_details, package_id,
                                                      package_version)
        end

        base_url = base_url.delete_suffix("/")
        package_id_downcased = package_id.downcase
        "#{base_url}/#{package_id_downcased}/#{package_version}/#{package_id_downcased}.#{package_version}.nupkg"
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def self.get_nuget_v3_package_url_from_search(repository_details, package_id, package_version)
        search_url = repository_details[:search_url]
        return nil unless search_url

        # get search result
        search_result_response = fetch_url(search_url, repository_details)
        return nil unless search_result_response.status == 200

        search_response_body = HttpResponseHelpers.remove_wrapping_zero_width_chars(search_result_response.body)
        search_results = JSON.parse(search_response_body)

        # find matching package and version
        package_search_result = search_results&.[]("data")&.find { |d| package_id.casecmp?(d&.[]("id")) }
        version_search_result = package_search_result&.[]("versions")&.find do |v|
          package_version.casecmp?(v&.[]("version"))
        end
        registration_leaf_url = version_search_result&.[]("@id")
        return nil unless registration_leaf_url

        registration_leaf_response = fetch_url(registration_leaf_url, repository_details)
        return nil unless registration_leaf_response
        return nil unless registration_leaf_response.status == 200

        registration_leaf_response_body =
          HttpResponseHelpers.remove_wrapping_zero_width_chars(registration_leaf_response.body)
        registration_leaf = JSON.parse(registration_leaf_response_body)

        # finally, get the .nupkg url
        registration_leaf&.[]("packageContent")
      end
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity

      def self.get_nuget_v2_package_url(repository_details, package_id, package_version)
        # get package XML
        base_url = repository_details[:base_url].delete_suffix("/")
        package_url = "#{base_url}/Packages(Id='#{package_id}',Version='#{package_version}')"
        response = fetch_url(package_url, repository_details)
        return nil unless response.status == 200

        # find relevant element
        doc = Nokogiri::XML(response.body)
        doc.remove_namespaces!

        content_element = doc.xpath("/entry/content")
        nupkg_url = content_element&.attribute("src")&.value
        nupkg_url
      end

      def self.fetch_stream(stream_url, auth_header, max_redirects = 5)
        current_url = stream_url
        current_redirects = 0

        loop do
          # Directly download the stream without any additional settings _except_ for `omit_default_port: true` which
          # is necessary to not break the URL signing that some NuGet feeds use.
          response = Excon.get(
            current_url,
            headers: auth_header,
            omit_default_port: true
          )

          # redirect the HTTP response as appropriate based on documentation here:
          # https://developer.mozilla.org/en-US/docs/Web/HTTP/Redirections
          case response.status
          when 200
            return response.body
          when 301, 302, 303, 307, 308
            current_redirects += 1
            return nil if current_redirects > max_redirects

            current_url = response.headers["Location"]
          else
            return nil
          end
        end
      end

      def self.fetch_url(url, repository_details)
        fetch_url_with_auth(url, repository_details.fetch(:auth_header))
      end

      def self.fetch_url_with_auth(url, auth_header)
        cache = CacheManager.cache("nupkg_fetcher_cache")
        cache[url] ||= Dependabot::RegistryClient.get(
          url: url,
          headers: auth_header
        )

        cache[url]
      end
    end
  end
end
