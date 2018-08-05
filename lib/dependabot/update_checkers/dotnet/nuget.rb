# frozen_string_literal: true

require "excon"
require "nokogiri"
require "dependabot/source"
require "dependabot/update_checkers/base"
require "dependabot/utils/dotnet/requirement"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Dotnet
      class Nuget < Dependabot::UpdateCheckers::Base
        require_relative "nuget/repository_finder"
        require_relative "nuget/requirements_updater"

        def latest_version
          @latest_version = latest_version_details&.fetch(:version)
        end

        def latest_resolvable_version
          # TODO: Check version resolution!
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # Irrelevant, since Nuget has a single dependency file
          nil
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            source_details: latest_version_details&.
                            slice(:nuspec_url, :repo_url, :source_url)
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Dotnet (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_version_details
          @latest_version_details =
            begin
              versions = available_versions
              unless wants_prerelease?
                versions.reject! { |hash| hash.fetch(:version).prerelease? }
              end
              versions.reject! do |hash|
                ignore_reqs.any? { |r| r.satisfied_by?(hash.fetch(:version)) }
              end
              versions.max_by { |hash| hash.fetch(:version) }
            end
        end

        def available_versions
          available_v3_versions + available_v2_versions
        end

        def available_v3_versions
          v3_nuget_listings.flat_map do |listing|
            listing.
              fetch("versions", []).
              map do |v|
                nuspec_url =
                  listing.fetch("listing_details").
                  fetch(:versions_url).
                  gsub(/index\.json$/, "#{v}/#{sanitized_name}.nuspec")

                {
                  version:    version_class.new(v),
                  nuspec_url: nuspec_url,
                  source_url: nil,
                  repo_url:
                    listing.fetch("listing_details").fetch(:repository_url)
                }
              end
          end
        end

        def available_v2_versions
          v2_nuget_listings.flat_map do |listing|
            body = listing.fetch("xml_body", [])
            doc = Nokogiri::XML(body)
            doc.remove_namespaces!

            doc.xpath("/feed/entry").map do |entry|
              version = entry.at_xpath("./properties/Version").content.strip
              source_urls = []
              [
                entry.at_xpath("./properties/ProjectUrl").content,
                entry.at_xpath("./properties/ReleaseNotes").content
              ].join(" ").scan(Source::SOURCE_REGEX) do
                source_urls << Regexp.last_match.to_s
              end

              source_url = source_urls.find { |url| Source.from_url(url) }
              source_url = Source.from_url(source_url)&.url if source_url

              {
                version:    version_class.new(version),
                nuspec_url: nil,
                source_url: source_url,
                repo_url:
                  listing.fetch("listing_details").fetch(:repository_url)
              }
            end
          end
        end

        def wants_prerelease?
          if dependency.version &&
             version_class.new(dependency.version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.include?("-") }
          end
        end

        def ignore_reqs
          ignored_versions.map do |req|
            Utils::Dotnet::Requirement.new(req.split(","))
          end
        end

        def v3_nuget_listings
          return @v3_nuget_listings unless @v3_nuget_listings.nil?

          dependency_urls.
            select { |details| details.fetch(:repository_type) == "v3" }.
            map do |url_details|
              response = Excon.get(
                url_details[:versions_url],
                headers: url_details[:auth_header],
                idempotent: true,
                **SharedHelpers.excon_defaults
              )
              next unless response.status == 200

              JSON.parse(response.body).merge("listing_details" => url_details)
            end.compact
        end

        def v2_nuget_listings
          return @v2_nuget_listings unless @v2_nuget_listings.nil?

          dependency_urls.
            select { |details| details.fetch(:repository_type) == "v2" }.
            map do |url_details|
              response = Excon.get(
                url_details[:versions_url],
                headers: url_details[:auth_header],
                idempotent: true,
                **SharedHelpers.excon_defaults
              )
              next unless response.status == 200

              {
                "xml_body" => response.body,
                "listing_details" => url_details
              }
            end.compact
        end

        def dependency_urls
          @dependency_urls ||=
            RepositoryFinder.new(
              dependency: dependency,
              credentials: credentials,
              config_file: nuget_config
            ).dependency_urls
        end

        def nuget_config
          @nuget_config ||=
            dependency_files.find { |f| f.name.casecmp("nuget.config").zero? }
        end

        def sanitized_name
          dependency.name.downcase
        end
      end
    end
  end
end
