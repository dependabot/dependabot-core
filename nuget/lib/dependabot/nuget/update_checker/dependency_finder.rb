# typed: false
# frozen_string_literal: true

require "nokogiri"
require "zip"
require "stringio"
require "dependabot/nuget/update_checker"
require "dependabot/nuget/version"

module Dependabot
  module Nuget
    class UpdateChecker
      class DependencyFinder
        require_relative "requirements_updater"

        def initialize(dependency:, dependency_files:, credentials:)
          @dependency             = dependency
          @dependency_files       = dependency_files
          @credentials            = credentials
        end

        def transitive_dependencies
          @transitive_dependencies ||= fetch_transitive_dependencies(
            @dependency.name,
            @dependency.version
          ).map do |dependency_info|
            package_name = dependency_info["packageName"]
            target_version = dependency_info["version"]

            Dependency.new(
              name: package_name,
              version: target_version.to_s,
              requirements: [], # Empty requirements for transitive dependencies
              package_manager: @dependency.package_manager
            )
          end
        end

        def updated_peer_dependencies
          @updated_peer_dependencies ||= fetch_transitive_dependencies(
            @dependency.name,
            @dependency.version
          ).filter_map do |dependency_info|
            package_name = dependency_info["packageName"]
            target_version = dependency_info["version"]

            # Find the Dependency object for the peer dependency. We will not return
            # dependencies that are not referenced from dependency files.
            peer_dependency = top_level_dependencies.find { |d| d.name == package_name }
            next unless peer_dependency
            next unless target_version > peer_dependency.numeric_version

            # Use version finder to determine the source details for the peer dependency.
            target_version_details = version_finder(peer_dependency).versions.find do |v|
              v.fetch(:version) == target_version
            end
            next unless target_version_details

            Dependency.new(
              name: peer_dependency.name,
              version: target_version_details.fetch(:version).to_s,
              requirements: updated_requirements(peer_dependency, target_version_details),
              previous_version: peer_dependency.version,
              previous_requirements: peer_dependency.requirements,
              package_manager: peer_dependency.package_manager,
              metadata: { information_only: true } # Instruct updater to not directly update this dependency
            )
          end
        end

        private

        attr_reader :dependency, :dependency_files, :credentials

        def updated_requirements(dep, target_version_details)
          @updated_requirements ||= {}
          @updated_requirements[dep.name] ||=
            RequirementsUpdater.new(
              requirements: dep.requirements,
              latest_version: target_version_details.fetch(:version).to_s,
              source_details: target_version_details
                          &.slice(:nuspec_url, :repo_url, :source_url)
            ).updated_requirements
        end

        def top_level_dependencies
          @top_level_dependencies ||=
            Nuget::FileParser.new(
              dependency_files: dependency_files,
              source: nil
            ).parse.select(&:top_level?)
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
            ).dependency_urls
                                           .select { |url| url.fetch(:repository_type) == "v3" }
        end

        def fetch_transitive_dependencies(package_id, package_version)
          all_dependencies = {}
          fetch_transitive_dependencies_impl(package_id, package_version, all_dependencies)
          all_dependencies.map { |_, dependency_info| dependency_info }
        end

        def fetch_transitive_dependencies_impl(package_id, package_version, all_dependencies)
          current_dependencies = fetch_dependencies(package_id, package_version)
          return unless current_dependencies.any?

          current_dependencies.each do |dependency|
            next if dependency.nil?

            dependency_id = dependency["packageName"]
            dependency_version_range = dependency["versionRange"]

            nuget_version_range_regex = /[\[(](\d+(\.\d+)*(-\w+(\.\d+)*)?)/
            nuget_version_range_match_data = nuget_version_range_regex.match(dependency_version_range)

            dependency_version = if nuget_version_range_match_data.nil?
                                   dependency_version_range
                                 else
                                   nuget_version_range_match_data[1]
                                 end

            dependency["version"] = Version.new(dependency_version)

            visited_dependency = all_dependencies[dependency_id.downcase]
            next unless visited_dependency.nil? || visited_dependency["version"] < dependency["version"]

            all_dependencies[dependency_id.downcase] = dependency
            fetch_transitive_dependencies_impl(dependency_id, dependency_version, all_dependencies)
          end
        end

        def fetch_dependencies(package_id, package_version)
          dependency_urls
            .flat_map do |url|
            Array(fetch_dependencies_from_repository(url, package_id, package_version))
              .compact
          end
        end

        def remove_wrapping_zero_width_chars(string)
          string.force_encoding("UTF-8").encode
                .gsub(/\A[\u200B-\u200D\uFEFF]/, "")
                .gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
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

        def fetch_dependencies_from_repository(repository_details, package_id, package_version) # rubocop:disable Metrics/PerceivedComplexity
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
            next unless dependency.attribute("version")

            dependency_list << {
              "packageName" => dependency.attribute("id").value,
              "versionRange" => dependency.attribute("version").value
            }
          end

          dependency_list
        end

        def version_finder(dep)
          VersionFinder.new(
            dependency: dep,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: [],
            raise_on_ignored: false,
            security_advisories: []
          )
        end
      end
    end
  end
end
