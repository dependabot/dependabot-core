# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"

require "dependabot/dependency"
require "dependabot/python/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder
        require_relative "index_finder"

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
        end

        def latest_version(python_version: nil)
          @latest_version ||=
            fetch_latest_version(python_version: python_version)
        end

        def latest_version_with_no_unlock(python_version: nil)
          @latest_version_with_no_unlock ||=
            fetch_latest_version_with_no_unlock(python_version: python_version)
        end

        def lowest_security_fix_version(python_version: nil)
          @lowest_security_fix_version ||=
            fetch_lowest_security_fix_version(python_version: python_version)
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories

        def fetch_latest_version(python_version:)
          versions = available_versions
          versions = filter_yanked_versions(versions)
          versions = filter_unsupported_versions(versions, python_version)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        def fetch_latest_version_with_no_unlock(python_version:)
          versions = available_versions
          versions = filter_yanked_versions(versions)
          versions = filter_unsupported_versions(versions, python_version)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_out_of_range_versions(versions)
          versions.max
        end

        def fetch_lowest_security_fix_version(python_version:)
          versions = available_versions
          versions = filter_yanked_versions(versions)
          versions = filter_unsupported_versions(versions, python_version)
          versions = filter_prerelease_versions(versions)
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(versions,
                                                                                           security_advisories)
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)

          versions.min
        end

        def filter_yanked_versions(versions_array)
          versions_array.reject { |details| details.fetch(:yanked) }
        end

        def filter_unsupported_versions(versions_array, python_version)
          versions_array.filter_map do |details|
            python_requirement = details.fetch(:python_requirement)
            next details.fetch(:version) unless python_version
            next details.fetch(:version) unless python_requirement
            next unless python_requirement.satisfied_by?(python_version)

            details.fetch(:version)
          end
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          filtered = versions_array.
                     reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise Dependabot::AllVersionsIgnored
          end

          filtered
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array.select { |version| version > dependency.numeric_version }
        end

        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.filter_map do |r|
            requirement_class.requirements_array(r.fetch(:requirement))
          end

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
              if index_response.status == 401 || index_response.status == 403
                registry_index_response = registry_index_response(index_url)

                if registry_index_response.status == 401 || registry_index_response.status == 403
                  raise PrivateSourceAuthenticationFailure, sanitized_url
                end
              end

              version_links = []
              index_response.body.scan(%r{<a\s.*?>.*?</a>}m) do
                details = version_details_from_link(Regexp.last_match.to_s)
                version_links << details if details
              end

              version_links.compact
            rescue Excon::Error::Timeout, Excon::Error::Socket
              raise if MAIN_PYPI_INDEXES.include?(index_url)

              raise PrivateSourceTimedOut, sanitized_url
            rescue URI::InvalidURIError
              raise DependencyFileNotResolvable, "Invalid URL: #{sanitized_url}"
            end
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def version_details_from_link(link)
          doc = Nokogiri::XML(link)
          filename = doc.at_css("a")&.content
          url = doc.at_css("a")&.attributes&.fetch("href", nil)&.value
          return unless filename&.match?(name_regex) || url&.match?(name_regex)

          version = get_version_from_filename(filename)
          return unless version_class.correct?(version)

          {
            version: version_class.new(version),
            python_requirement: build_python_requirement_from_link(link),
            yanked: link&.include?("data-yanked")
          }
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def get_version_from_filename(filename)
          filename.
            gsub(/#{name_regex}-/i, "").
            split(/-|\.tar\.|\.zip|\.whl/).
            first
        end

        def build_python_requirement_from_link(link)
          req_string = Nokogiri::XML(link).
                       at_css("a")&.
                       attribute("data-requires-python")&.
                       content

          return unless req_string

          requirement_class.new(CGI.unescapeHTML(req_string))
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        def index_urls
          @index_urls ||=
            IndexFinder.new(
              dependency_files: dependency_files,
              credentials: credentials
            ).index_urls
        end

        def registry_response_for_dependency(index_url)
          Dependabot::RegistryClient.get(
            url: index_url + normalised_name + "/",
            headers: { "Accept" => "text/html" }
          )
        end

        def registry_index_response(index_url)
          Dependabot::RegistryClient.get(
            url: index_url,
            headers: { "Accept" => "text/html" }
          )
        end

        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        def normalised_name
          NameNormaliser.normalise(dependency.name)
        end

        def name_regex
          parts = normalised_name.split(/[\s_.-]/).map { |n| Regexp.quote(n) }
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
