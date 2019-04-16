# frozen_string_literal: true

require "excon"

require "dependabot/python/update_checker"
require "dependabot/shared_helpers"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder
        require_relative "index_finder"

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:)
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_version_with_no_unlock
          @latest_version_with_no_unlock ||=
            fetch_latest_version_with_no_unlock
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions

        def fetch_latest_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        def fetch_latest_version_with_no_unlock
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_out_of_range_versions(versions)
          versions.max
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          versions_array.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
        end

        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.map do |r|
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

        # See https://www.python.org/dev/peps/pep-0503/ for details of the
        # Simple Repository API we use here.
        def available_versions
          @available_versions ||=
            index_urls.flat_map do |index_url|
              sanitized_url = index_url.gsub(%r{(?<=//).*(?=@)}, "redacted")
              index_response = registry_response_for_dependency(index_url)

              if [401, 403].include?(index_response.status) &&
                 [401, 403].include?(registry_index_response(index_url).status)
                raise PrivateSourceAuthenticationFailure, sanitized_url
              end

              index_response.body.
                scan(%r{<a\s.*?>(.*?)</a>}m).flatten.
                select { |n| n.match?(name_regex) }.
                map do |filename|
                  version =
                    filename.
                    gsub(/#{name_regex}-/i, "").
                    split(/-|\.tar\.|\.zip|\.whl/).
                    first
                  next unless version_class.correct?(version)

                  version_class.new(version)
                end.compact
            rescue Excon::Error::Timeout, Excon::Error::Socket
              raise if MAIN_PYPI_INDEXES.include?(index_url)

              raise PrivateSourceAuthenticationFailure, sanitized_url
            end
        end

        def index_urls
          @index_urls ||=
            IndexFinder.new(
              dependency_files: dependency_files,
              credentials: credentials
            ).index_urls
        end

        def registry_response_for_dependency(index_url)
          Excon.get(
            index_url + normalised_name + "/",
            idempotent: true,
            **SharedHelpers.excon_defaults
          )
        end

        def registry_index_response(index_url)
          Excon.get(
            index_url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )
        end

        def ignore_reqs
          ignored_versions.map { |req| requirement_class.new(req.split(",")) }
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name
          dependency.name.downcase.gsub(/[-_.]+/, "-")
        end

        def name_regex
          parts = dependency.name.split(/[\s_.-]/).map { |n| Regexp.quote(n) }
          /#{parts.join("[\s_.-]")}/i
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
