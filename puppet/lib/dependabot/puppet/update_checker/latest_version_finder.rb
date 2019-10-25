# frozen_string_literal: true

require "excon"

require "dependabot/dependency"
require "dependabot/puppet/update_checker"
require "dependabot/shared_helpers"

module Dependabot
  module Puppet
    class UpdateChecker
      class LatestVersionFinder
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_version_with_no_unlock
          @latest_version_with_no_unlock ||= fetch_latest_version_with_no_unlock
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories

        def fetch_latest_version
          versions = available_versions
          versions = filter_yanked_versions(versions)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        def fetch_latest_version_with_no_unlock
          versions = available_versions
          versions = filter_yanked_versions(versions)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_out_of_range_versions(versions)
          versions.max
        end

        def fetch_lowest_security_fix_version
          versions = available_versions
          versions = filter_yanked_versions(versions)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_vulnerable_versions(versions)
          versions = filter_lower_versions(versions)
          versions.min
        end

        def filter_yanked_versions(versions_array)
          versions_array.
            reject { |details| details.fetch(:yanked) }.
            map { |details| details.fetch(:version) }
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          versions_array.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
        end

        def filter_vulnerable_versions(versions_array)
          versions_array.
            reject { |v| security_advisories.any? { |a| a.vulnerable?(v) } }
        end

        def filter_lower_versions(versions_array)
          versions_array.
            select { |version| version > version_class.new(dependency.version) }
        end

        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.map do |r|
            next unless r.fetch(:requirement)

            requirement_class.requirements_array(r.fetch(:requirement))
          end.compact

          versions_array.
            select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
        end

        def wants_prerelease?
          if dependency.version
            version = version_class.new(dependency.version.tr("+", "."))
            return version.prerelease?
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        def available_versions
          @available_versions ||=
            puppet_forge_details.
            fetch("releases", []).
            map do |release|
              {
                version: version_class.new(release.fetch("version")),
                yanked: !release.fetch("deleted_at").nil?
              }
            end
        end

        def puppet_forge_details
          return @puppet_forge_details unless @puppet_forge_details.nil?

          response = Excon.get(
            puppet_forge_url(dependency.name),
            headers: { "User-Agent" => "dependabot-puppet/0.1.0" },
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          @puppet_forge_details = JSON.parse(response.body)
        rescue JSON::ParserError, Excon::Error::Timeout
          @puppet_forge_details = {}
        end

        def puppet_forge_url(module_name)
          "https://forgeapi.puppet.com/v3/modules/#{module_name}"\
          "?exclude_fields=readme,license,changelog,reference"
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end
      end
    end
  end
end
