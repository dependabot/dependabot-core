# typed: false
# frozen_string_literal: true

require "dependabot/nuget/version"
require "dependabot/nuget/requirement"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "dependabot/nuget/nuget_client"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class VersionFinder
        require_relative "compatibility_checker"
        require_relative "repository_finder"

        NUGET_RANGE_REGEX = /[\(\[].*,.*[\)\]]/

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:,
                       repo_contents_path:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
          @repo_contents_path  = repo_contents_path
        end

        def latest_version_details
          @latest_version_details ||=
            begin
              possible_versions = versions
              possible_versions = filter_prereleases(possible_versions)
              possible_versions = filter_ignored_versions(possible_versions)

              find_highest_compatible_version(possible_versions)
            end
        end

        def lowest_security_fix_version_details
          @lowest_security_fix_version_details ||=
            begin
              possible_versions = versions
              possible_versions = filter_prereleases(possible_versions)
              possible_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
                possible_versions, security_advisories
              )
              possible_versions = filter_ignored_versions(possible_versions)
              possible_versions = filter_lower_versions(possible_versions)

              find_lowest_compatible_version(possible_versions)
            end
        end

        def versions
          available_v3_versions + available_v2_versions
        end

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories, :repo_contents_path

        private

        def find_highest_compatible_version(possible_versions)
          # sorted versions descending
          sorted_versions = possible_versions.sort_by { |v| v.fetch(:version) }.reverse
          find_compatible_version(sorted_versions)
        end

        def find_lowest_compatible_version(possible_versions)
          # sorted versions ascending
          sorted_versions = possible_versions.sort_by { |v| v.fetch(:version) }
          find_compatible_version(sorted_versions)
        end

        def find_compatible_version(sorted_versions)
          # By checking the first version separately, we can avoid additional network requests
          first_version = sorted_versions.first
          return unless first_version
          # If the current package version is incompatible, then we don't enforce compatibility.
          # It could appear incompatible because they are ignoring NU1701 or the package is poorly authored.
          return first_version unless version_compatible?(dependency.version)

          # once sorted by version, the best we can do is search every package, because it's entirely possible for there
          # to be incompatible packages both with a higher and lower version number, so no smart searching can be done.
          sorted_versions.find { |v| version_compatible?(v.fetch(:version)) }
        end

        def version_compatible?(version)
          str_version_compatible?(version.to_s)
        end

        def str_version_compatible?(version)
          compatibility_checker.compatible?(version)
        end

        def compatibility_checker
          @compatibility_checker ||= CompatibilityChecker.new(
            dependency_urls: dependency_urls,
            dependency: dependency,
            tfm_finder: TfmFinder.new(
              dependency_files: dependency_files,
              credentials: credentials,
              repo_contents_path: repo_contents_path
            )
          )
        end

        def filter_prereleases(possible_versions)
          filtered = possible_versions.reject do |d|
            version = d.fetch(:version)
            version.prerelease? && !related_to_current_pre?(version)
          end
          if possible_versions.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_versions.count - filtered.count} pre-release versions")
          end
          filtered
        end

        def filter_ignored_versions(possible_versions)
          filtered = possible_versions

          ignored_versions.each do |req|
            ignore_req = requirement_class.new(parse_requirement_string(req))
            filtered =
              filtered
              .reject { |v| ignore_req.satisfied_by?(v.fetch(:version)) }
          end

          if @raise_on_ignored && filter_lower_versions(filtered).empty? &&
             filter_lower_versions(possible_versions).any?
            raise AllVersionsIgnored
          end

          if possible_versions.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_versions.count - filtered.count} ignored versions")
          end

          filtered
        end

        def filter_lower_versions(possible_versions)
          return possible_versions unless dependency.numeric_version

          possible_versions.select do |v|
            v.fetch(:version) > dependency.numeric_version
          end
        end

        def parse_requirement_string(string)
          return [string] if string.match?(NUGET_RANGE_REGEX)

          string.split(",").map(&:strip)
        end

        def available_v3_versions
          v3_nuget_listings.flat_map do |listing|
            listing
              .fetch("versions", [])
              .map do |v|
                listing_details = listing.fetch("listing_details")
                nuspec_url = listing_details
                             .fetch(:versions_url, nil)
                             &.gsub(/index\.json$/, "#{v}/#{sanitized_name}.nuspec")

                {
                  version: version_class.new(v),
                  nuspec_url: nuspec_url,
                  source_url: nil,
                  repo_url: listing_details.fetch(:repository_url)
                }
              end
          end
        end

        def available_v2_versions
          v2_nuget_listings.flat_map do |listing|
            body = listing.fetch("xml_body", [])
            doc = Nokogiri::XML(body)
            doc.remove_namespaces!

            doc.xpath("/feed/entry").filter_map do |entry|
              listed = entry.at_xpath("./properties/Listed")&.content&.strip
              next if listed&.casecmp("false")&.zero?

              entry_details = dependency_details_from_v2_entry(entry)
              entry_details.merge(
                repo_url: listing.fetch("listing_details")
                          .fetch(:repository_url)
              )
            end
          end
        end

        def dependency_details_from_v2_entry(entry)
          version = entry.at_xpath("./properties/Version").content.strip
          source_urls = []
          [
            entry.at_xpath("./properties/ProjectUrl")&.content,
            entry.at_xpath("./properties/ReleaseNotes")&.content
          ].compact.join(" ").scan(Source::SOURCE_REGEX) do
            source_urls << Regexp.last_match.to_s
          end

          source_url = source_urls.find { |url| Source.from_url(url) }
          source_url = Source.from_url(source_url)&.url if source_url

          {
            version: version_class.new(version),
            nuspec_url: nil,
            source_url: source_url
          }
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def related_to_current_pre?(version)
          current_version = dependency.numeric_version
          if current_version&.prerelease? &&
             current_version&.release == version.release
            return true
          end

          dependency.requirements.any? do |req|
            reqs = parse_requirement_string(req.fetch(:requirement) || "")
            return true if reqs.any?("*-*")
            next unless reqs.any? { |r| r.include?("-") }

            requirement_class
              .requirements_array(req.fetch(:requirement))
              .any? do |r|
                r.requirements.any? { |a| a.last.release == version.release }
              end
          rescue Gem::Requirement::BadRequirementError
            false
          end
        end

        # rubocop:enable Metrics/PerceivedComplexity

        def v3_nuget_listings
          return @v3_nuget_listings unless @v3_nuget_listings.nil?

          @v3_nuget_listings ||=
            dependency_urls
            .select { |details| details.fetch(:repository_type) == "v3" }
            .filter_map do |url_details|
              versions = NugetClient.get_package_versions(dependency.name, url_details)
              next unless versions

              { "versions" => versions, "listing_details" => url_details }
            end
        end

        def v2_nuget_listings
          return @v2_nuget_listings unless @v2_nuget_listings.nil?

          @v2_nuget_listings ||=
            dependency_urls
            .select { |details| details.fetch(:repository_type) == "v2" }
            .flat_map { |url_details| fetch_paginated_v2_nuget_listings(url_details) }
            .filter_map do |url_details, response|
              next unless response.status == 200

              {
                "xml_body" => response.body,
                "listing_details" => url_details
              }
            end
        end

        def fetch_paginated_v2_nuget_listings(url_details, results = {})
          response = Dependabot::RegistryClient.get(
            url: url_details[:versions_url],
            headers: url_details[:auth_header]
          )

          # NOTE: Short circuit if we get a circular next link
          return results.to_a if results.key?(url_details)

          results[url_details] = response

          if (link_href = fetch_v2_next_link_href(response.body))
            url_details = url_details.dup
            # Some Nuget repositories, such as JFrog's Artifactory, URL encode the "next" href
            # link in the paged results. If the href is not URL decoded, the paging parameters
            # are ignored and the first page is always returned.
            url_details[:versions_url] = CGI.unescape(link_href)
            fetch_paginated_v2_nuget_listings(url_details, results)
          end

          results.to_a
        end

        def fetch_v2_next_link_href(xml_body)
          doc = Nokogiri::XML(xml_body)
          doc.remove_namespaces!
          link_node = doc.xpath("/feed/link").find do |node|
            rel = node.attribute("rel").value.strip
            rel == "next"
          end
          link_node.attribute("href").value.strip if link_node
        rescue Nokogiri::XML::XPath::SyntaxError
          nil
        end

        def dependency_urls
          @dependency_urls ||=
            RepositoryFinder.new(
              dependency: dependency,
              credentials: credentials,
              config_files: nuget_configs
            ).dependency_urls
        end

        def nuget_configs
          @nuget_configs ||=
            dependency_files.select { |f| f.name.match?(/nuget\.config$/i) }
        end

        def sanitized_name
          dependency.name.downcase
        end

        def version_class
          dependency.version_class
        end

        def requirement_class
          dependency.requirement_class
        end

        def excon_options
          # For large JSON files we sometimes need a little longer than for
          # other languages. For example, see:
          # https://dotnet.myget.org/F/aspnetcore-dev/api/v3/query?
          # q=microsoft.aspnetcore.mvc&prerelease=true&semVerLevel=2.0.0
          {
            connect_timeout: 30,
            write_timeout: 30,
            read_timeout: 30
          }
        end
      end
    end
  end
end
