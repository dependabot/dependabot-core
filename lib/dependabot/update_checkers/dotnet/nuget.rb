# frozen_string_literal: true

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
                            slice(:nuspec_url, :repo_url)
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
          nuget_listings.flat_map do |listing|
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

        def nuget_listings
          return @nuget_listings unless @nuget_listings.nil?

          v3_dependency_urls.map do |url_details|
            response = Excon.get(
              url_details[:versions_url],
              headers: url_details[:auth_header],
              idempotent: true,
              **SharedHelpers.excon_defaults
            )
            next unless response.status == 200

            @nuget_listing =
              JSON.parse(response.body).
              merge("listing_details" => url_details)
          end.compact
        end

        def v3_dependency_urls
          @v3_dependency_urls ||=
            RepositoryFinder.new(
              dependency: dependency,
              credentials: credentials,
              config_file: nuget_config
            ).v3_dependency_urls
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
