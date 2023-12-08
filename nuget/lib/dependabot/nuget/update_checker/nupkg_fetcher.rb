# typed: true
# frozen_string_literal: true

require "nokogiri"
require "zip"
require "stringio"
require "dependabot/nuget/update_checker"

module Dependabot
  module Nuget
    class UpdateChecker
      class NupkgFetcher
        require_relative "repository_finder"

        def self.fetch_nupkg_buffer(dependency_urls, package_id, package_version)
          # check all repositories for the first one that has the nupkg
          dependency_urls.reduce(nil) do |nupkg_buffer, repository_details|
            nupkg_buffer || fetch_nupkg_buffer_from_repository(repository_details, package_id, package_version)
          end
        end

        def self.fetch_nupkg_buffer_from_repository(repository_details, package_id, package_version)
          return unless package_id && package_version && !package_version.empty?

          feed_url = repository_details[:repository_url]
          auth_header = repository_details[:auth_header]

          azure_devops_match = try_match_azure_url(feed_url)
          package_url = if azure_devops_match
                          get_azure_package_url(azure_devops_match, package_id, package_version)
                        elsif feed_url.include?("/v2")
                          get_nuget_v2_package_url(feed_url, package_id, package_version)
                        elsif feed_url.include?("/v3")
                          get_nuget_v3_package_url(feed_url, package_id, package_version)
                        else
                          raise Dependabot::DependencyFileNotResolvable, "Unexpected NuGet feed format: #{feed_url}"
                        end

          fetch_stream(package_url, auth_header)
        end

        def self.try_match_azure_url(feed_url)
          # if url is azure devops
          azure_devops_regexs = [
            %r{https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/(?<project>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json},
            %r{https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json(?<project>)},
            %r{https://(?<organization>[^\.\/]+)\.pkgs\.visualstudio\.com/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json(?<project>)}
          ]
          regex = azure_devops_regexs.find { |reg| reg.match(feed_url) }
          return unless regex

          regex.match(feed_url)
        end

        def self.get_azure_package_url(azure_devops_match, package_id, package_version)
          organization = azure_devops_match[:organization]
          project = azure_devops_match[:project]
          feed_id = azure_devops_match[:feedId]

          if project.empty?
            "https://pkgs.dev.azure.com/#{organization}/_apis/packaging/feeds/#{feed_id}/nuget/packages/#{package_id}/versions/#{package_version}/content?sourceProtocolVersion=nuget&api-version=7.0-preview"
          else
            "https://pkgs.dev.azure.com/#{organization}/#{project}/_apis/packaging/feeds/#{feed_id}/nuget/packages/#{package_id}/versions/#{package_version}/content?sourceProtocolVersion=nuget&api-version=7.0-preview"
          end
        end

        def self.get_nuget_v3_package_url(feed_url, package_id, package_version)
          base_url = feed_url.gsub("/index.json", "-flatcontainer")
          package_id_downcased = package_id.downcase
          "#{base_url}/#{package_id_downcased}/#{package_version}/#{package_id_downcased}.#{package_version}.nupkg"
        end

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

            if response.status == 303
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
      end
    end
  end
end
