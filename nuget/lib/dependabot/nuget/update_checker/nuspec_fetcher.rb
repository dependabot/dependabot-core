# typed: true
# frozen_string_literal: true

require "nokogiri"
require "zip"
require "stringio"
require "dependabot/nuget/update_checker"

module Dependabot
  module Nuget
    class UpdateChecker
      class NuspecFetcher
        require_relative "nupkg_fetcher"
        require_relative "repository_finder"

        def self.fetch_nuspec(dependency_urls, package_id, package_version)
          # check all repositories for the first one that has the nuspec
          dependency_urls.reduce(nil) do |nuspec_xml, repository_details|
            nuspec_xml || fetch_nuspec_from_repository(repository_details, package_id, package_version)
          end
        end

        def self.fetch_nuspec_from_repository(repository_details, package_id, package_version)
          return unless package_id && package_version && !package_version.empty?

          feed_url = repository_details[:repository_url]
          auth_header = repository_details[:auth_header]

          nuspec_xml = nil

          if azure_package_feed?(feed_url)
            # this is an azure devops url we can extract the nuspec from the nupkg
            package_data = NupkgFetcher.fetch_nupkg_buffer_from_repository(repository_details, package_id,
                                                                           package_version)
            return if package_data.nil?

            nuspec_string = extract_nuspec(package_data, package_id)
            nuspec_xml = Nokogiri::XML(nuspec_string)
          else
            # we can use the normal nuget apis to get the nuspec and list out the dependencies
            base_url = feed_url.gsub("/index.json", "-flatcontainer")
            package_id_downcased = package_id.downcase
            nuspec_url = "#{base_url}/#{package_id_downcased}/#{package_version}/#{package_id_downcased}.nuspec"

            nuspec_response = Dependabot::RegistryClient.get(
              url: nuspec_url,
              headers: auth_header
            )

            return unless nuspec_response.status == 200

            nuspec_response_body = remove_wrapping_zero_width_chars(nuspec_response.body)
            nuspec_xml = Nokogiri::XML(nuspec_response_body)
          end

          nuspec_xml.remove_namespaces!
          nuspec_xml
        end

        def self.azure_package_feed?(feed_url)
          # if url is azure devops
          azure_devops_regexs = [
            %r{https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/(?<project>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json},
            %r{https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json(?<project>)},
            %r{https://(?<organization>[^\.\/]+)\.pkgs\.visualstudio\.com/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json(?<project>)}
          ]
          azure_devops_regexs.any? { |reg| reg.match(feed_url) }
        end

        def self.extract_nuspec(zip_stream, package_id)
          Zip::File.open_buffer(zip_stream) do |zip|
            nuspec_entry = zip.find { |entry| entry.name == "#{package_id}.nuspec" }
            return nuspec_entry.get_input_stream.read if nuspec_entry
          end
          nil
        end

        def self.remove_wrapping_zero_width_chars(string)
          string.force_encoding("UTF-8").encode
                .gsub(/\A[\u200B-\u200D\uFEFF]/, "")
                .gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
        end
      end
    end
  end
end
