# frozen_string_literal: true

require "nokogiri"
require "zip"
require "stringio"
require "dependabot/nuget/file_updater"
require "dependabot/nuget/update_checker"

module Dependabot
  module Nuget
    class FileUpdater
      class DependencyFinder
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
        end

        def dependencies
          @dependencies ||= fetch_all_dependencies(@dependency.name, @dependency.version)
        end

        def nuget_configs
          @nuget_configs ||=
            @dependency_files.select { |f| f.name.match?(/nuget\.config$/i) }
        end

        def dependency_urls
          @dependency_urls ||=
            UpdateChecker::RepositoryFinder.new(
              dependency: @dependency,
              credentials: @credentials,
              config_files: nuget_configs
            ).dependency_urls.
            select { |url| url.fetch(:repository_type) == "v3" }
        end

        def fetch_all_dependencies(package_id, package_version)
          all_dependencies = Set.new
          fetch_all_dependencies_impl(package_id, package_version, all_dependencies)
          all_dependencies
        end

        def fetch_all_dependencies_impl(package_id, package_version, all_dependencies)
          current_dependencies = fetch_dependencies(package_id, package_version)
          return unless current_dependencies.any?

          current_dependencies.each do |dependency|
            next if dependency.nil?
            next if all_dependencies.include?(dependency)

            dependency_id = dependency["packageName"]
            dependency_version_range = dependency["versionRange"]

            nuget_version_range_regex = /[\[(](\d+(\.\d+)*(-\w+(\.\d+)*)?)/
            nuget_version_range_match_data = nuget_version_range_regex.match(dependency_version_range)

            dependency_version = if nuget_version_range_match_data.nil?
                                   dependency_version_range
                                 else
                                   nuget_version_range_match_data[1]
                                 end

            all_dependencies.add(dependency)
            fetch_all_dependencies_impl(dependency_id, dependency_version, all_dependencies)
          end
        end

        def fetch_dependencies(package_id, package_version)
          dependency_urls.
            flat_map do |url|
            Array(fetch_dependencies_from_repository(url, package_id, package_version)).
              compact
          end
        end

        def remove_wrapping_zero_width_chars(string)
          string.force_encoding("UTF-8").encode.
            gsub(/\A[\u200B-\u200D\uFEFF]/, "").
            gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
        end

        def extract_nuspec(zip_stream, package_id)
          Zip::File.open_buffer(zip_stream) do |zip|
            nuspec_entry = zip.find { |entry| entry.name == "#{package_id}.nuspec" }
            return nuspec_entry.get_input_stream.read if nuspec_entry
          end
          nil
        end

        def fetch_stream(stream_url, auth_header, max_redirects = 5)
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

        def fetch_nuspec(feed_url, package_id, package_version, auth_header)
          # if url is azure devops
          azure_devops_regex = %r{https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/(?<project>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json}
          azure_devops_match = azure_devops_regex.match(feed_url)
          nuspec_xml = nil

          if azure_devops_match
            # this is an azure devops url we will need to use a different code path to lookup dependencies
            organization = azure_devops_match[:organization]
            project = azure_devops_match[:project]
            feed_id = azure_devops_match[:feedId]

            package_url = "https://pkgs.dev.azure.com/#{organization}/#{project}/_apis/packaging/feeds/#{feed_id}/nuget/packages/#{package_id}/versions/#{package_version}/content?sourceProtocolVersion=nuget&api-version=7.0-preview"

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

        def fetch_dependencies_from_repository(repository_details, package_id, package_version)
          feed_url = repository_details[:repository_url]
          nuspec_xml = fetch_nuspec(feed_url, package_id, package_version, repository_details[:auth_header])

          return if nuspec_xml.nil?

          # we want to exclude development dependencies from the lookup
          allowed_attributes = %w(all compile native runtime)

          nuspec_xml_dependencies = nuspec_xml.xpath("//dependencies/child::node()/dependency").select do |dependency|
            include_attr = dependency.attribute("include")
            exclude_attr = dependency.attribute("exclude")

            if include_attr.nil? && exclude_attr.nil?
              true
            elsif include_attr
              include_values = include_attr.value.split(",").map(&:strip)
              include_values.any? { |element1| allowed_attributes.any? { |element2| element1.casecmp?(element2) } }
            else
              exclude_values = exclude_attr.value.split(",").map(&:strip)
              exclude_values.none? { |element1| allowed_attributes.any? { |element2| element1.casecmp?(element2) } }
            end
          end

          dependency_list = []
          nuspec_xml_dependencies.each do |dependency|
            dependency_list << {
              "packageName" => dependency.attribute("id").value,
              "versionRange" => dependency.attribute("version").value
            }
          end

          dependency_list
        end
      end
    end
  end
end
