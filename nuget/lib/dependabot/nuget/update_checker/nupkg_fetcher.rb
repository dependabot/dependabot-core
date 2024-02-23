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
                        get_nuget_v2_package_url(feed_url, package_id, package_version)
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

        registration_leaf_response = fetch_url(registration_leaf_url, repository_details)
        return nil unless registration_leaf_response.status == 200

        registration_leaf_response_body =
          HttpResponseHelpers.remove_wrapping_zero_width_chars(registration_leaf_response.body)
        registration_leaf = JSON.parse(registration_leaf_response_body)

        # finally, get the .nupkg url
        registration_leaf&.[]("packageContent")
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def self.get_nuget_v2_package_url(feed_url, package_id, package_version)
        base_url = feed_url
        base_url += "/" unless base_url.end_with?("/")
        package_id_downcased = package_id.downcase
        "#{base_url}/package/#{package_id_downcased}/#{package_version}"
      end

      def self.fetch_stream(stream_url, auth_header, max_redirects = 5)
        current_url = stream_url
        current_redirects = 0

        loop do
          connection = Excon.new(current_url, persistent: true)

          package_data = StringIO.new
          response_block = lambda do |chunk, _remaining_bytes, _total_bytes|
            package_data.write(chunk)
          end

          response = connection.request(
            method: :get,
            headers: auth_header,
            response_block: response_block
          )

          if response.status == 303 || response.status == 307
            current_redirects += 1
            return nil if current_redirects > max_redirects

            current_url = response.headers["Location"]
          elsif response.status == 200
            package_data.rewind
            return package_data
          else
            return nil
          end
        end
      end

      def self.fetch_url(url, repository_details)
        cache = CacheManager.cache("nupkg_fetcher_cache")
        cache[url] ||= Dependabot::RegistryClient.get(
          url: url,
          headers: repository_details.fetch(:auth_header)
        )

        cache[url]
      end
    end
  end
end
