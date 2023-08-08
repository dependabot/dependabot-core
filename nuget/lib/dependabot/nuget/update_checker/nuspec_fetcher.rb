# typed: false
# frozen_string_literal: true

require "nokogiri"
require "zip"
require "stringio"
require "dependabot/nuget/update_checker"

module Dependabot
  module Nuget
    class UpdateChecker
      class NuspecFetcher
        def self.fetch_nuspec(repository_details, package_id, package_version)
          return unless package_id && package_version && !package_version.empty?

          feed_url = repository_details[:repository_url]
          auth_header = repository_details[:auth_header]

          nuspec_xml = nil

          azure_devops_match = try_match_azure_url(feed_url)
          if azure_devops_match
            # this is an azure devops url we will need to use a different code path to lookup dependencies
            package_url = get_azure_package_url(azure_devops_match, package_id, package_version)
            package_data = fetch_stream(package_url, auth_header)

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
