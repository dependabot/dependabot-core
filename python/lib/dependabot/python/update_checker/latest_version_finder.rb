# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/python/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored: false
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored

          @latest_version = T.let(nil, T.nilable(Dependabot::Version))
          @latest_version_with_no_unlock = T.let(nil, T.nilable(Dependabot::Version))
          @lowest_security_fix_version = T.let(nil, T.nilable(Dependabot::Version))
          @available_versions = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          @index_urls = T.let(nil, T.nilable(T::Array[String]))
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Gem::Version))
        end
        def latest_version(python_version: nil)
          @latest_version ||= fetch_latest_version(python_version: python_version)
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Gem::Version))
        end
        def latest_version_with_no_unlock(python_version: nil)
          @latest_version_with_no_unlock ||= fetch_latest_version_with_no_unlock(python_version: python_version)
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Gem::Version))
        end
        def lowest_security_fix_version(python_version: nil)
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version(python_version: python_version)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[SecurityAdvisory]) }
        attr_reader :security_advisories

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(python_version:)
          version_hashes = available_versions
          return unless version_hashes

          version_hashes = filter_yanked_versions(version_hashes)
          versions = filter_unsupported_versions(version_hashes, python_version)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)

          versions.max
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version_with_no_unlock(python_version:)
          version_hashes = available_versions
          return unless version_hashes

          version_hashes = filter_yanked_versions(version_hashes)
          versions = filter_unsupported_versions(version_hashes, python_version)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_out_of_range_versions(versions)

          versions.max
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(python_version:)
          version_hashes = available_versions
          return unless version_hashes

          version_hashes = filter_yanked_versions(version_hashes)
          versions = filter_unsupported_versions(version_hashes, python_version)
          # versions = filter_prerelease_versions(versions)
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
            versions,
            security_advisories
          )
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)

          versions.min
        end

        sig do
          params(versions_array: T::Array[T::Hash[Symbol, T.untyped]])
            .returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def filter_yanked_versions(versions_array)
          filtered = versions_array.reject { |details| details.fetch(:yanked) }
          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} yanked versions")
          end
          filtered
        end

        sig do
          params(
            versions_array: T::Array[T::Hash[Symbol, T.untyped]],
            python_version: T.nilable(T.any(String, Version))
          )
            .returns(T::Array[Dependabot::Version])
        end
        def filter_unsupported_versions(versions_array, python_version)
          filtered = versions_array.filter_map do |details|
            python_requirement = details.fetch(:python_requirement)
            next details.fetch(:version) unless python_version
            next details.fetch(:version) unless python_requirement
            next unless python_requirement.satisfied_by?(python_version)

            details.fetch(:version)
          end
          if versions_array.count > filtered.count
            delta = versions_array.count - filtered.count
            Dependabot.logger.info("Filtered out #{delta} unsupported Python #{python_version} versions")
          end
          filtered
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          filtered = versions_array.reject(&:prerelease?)

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} pre-release versions")
          end

          filtered
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_ignored_versions(versions_array)
          filtered = versions_array
                     .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise Dependabot::AllVersionsIgnored
          end

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} ignored versions")
          end
          filtered
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array.select { |version| version > dependency.numeric_version }
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.filter_map do |r|
            requirement_class.requirements_array(r.fetch(:requirement))
          end

          versions_array
            .select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return version_class.new(dependency.version).prerelease? if dependency.version

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        # See https://www.python.org/dev/peps/pep-0503/ for details of the
        # Simple Repository API we use here.
        sig do
          returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
        end
        def available_versions
          @available_versions ||=
            index_urls.flat_map do |index_url|
              sanitized_url = index_url.gsub(%r{(?<=//)[^/@]+(?=@)}, "redacted")

              begin
                validate_index(index_url)

                index_response = registry_response_for_dependency(index_url)
                if index_response.status == 401 || index_response.status == 403
                  registry_index_response = registry_index_response(index_url)

                  if registry_index_response.status == 401 || registry_index_response.status == 403
                    raise PrivateSourceAuthenticationFailure, sanitized_url
                  end
                end

                version_links = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
                index_response.body.scan(%r{<a\s[^>]*?>.*?<\/a>}m) do
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
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig do
          params(link: T.nilable(String))
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def version_details_from_link(link)
          return unless link

          doc = Nokogiri::XML(link)
          filename = doc.at_css("a")&.content
          url = doc.at_css("a")&.attributes&.fetch("href", nil)&.value

          return unless filename&.match?(name_regex) || url&.match?(name_regex)

          version = get_version_from_filename(filename)
          return unless version_class.correct?(version)

          {
            version: version_class.new(version),
            python_requirement: build_python_requirement_from_link(link),
            yanked: link.include?("data-yanked")
          }
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(filename: String).returns(T.nilable(String)) }
        def get_version_from_filename(filename)
          filename
            .gsub(/#{name_regex}-/i, "")
            .split(/-|\.tar\.|\.zip|\.whl/)
            .first
        end

        sig { params(link: String).returns(T.nilable(Dependabot::Requirement)) }
        def build_python_requirement_from_link(link)
          req_string = Nokogiri::XML(link)
                               .at_css("a")
                               &.attribute("data-requires-python")
                               &.content

          return unless req_string

          requirement_class.new(CGI.unescapeHTML(req_string))
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig { returns(T::Array[String]) }
        def index_urls
          @index_urls ||=
            Package::PackageRegistryFinder.new(
              dependency_files: dependency_files,
              credentials: credentials,
              dependency: dependency
            ).registry_urls
        end

        sig { params(index_url: String).returns(Excon::Response) }
        def registry_response_for_dependency(index_url)
          Dependabot::RegistryClient.get(
            url: index_url + normalised_name + "/",
            headers: { "Accept" => "text/html" }
          )
        end

        sig { params(index_url: String).returns(Excon::Response) }
        def registry_index_response(index_url)
          Dependabot::RegistryClient.get(
            url: index_url,
            headers: { "Accept" => "text/html" }
          )
        end

        sig { returns(T::Array[T.untyped]) }
        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        sig { returns(String) }
        def normalised_name
          NameNormaliser.normalise(dependency.name)
        end

        sig { returns(Regexp) }
        def name_regex
          parts = normalised_name.split(/[\s_.-]/).map { |n| Regexp.quote(n) }
          /#{parts.join("[\s_.-]")}/i
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end

        sig { params(index_url: T.nilable(String)).void }
        def validate_index(index_url)
          return unless index_url

          sanitized_url = index_url.gsub(%r{(?<=//)[^/@]+(?=@)}, "redacted")

          return if index_url.match?(URI::DEFAULT_PARSER.regexp[:ABS_URI])

          raise Dependabot::DependencyFileNotResolvable,
                "Invalid URL: #{sanitized_url}"
        end
      end
    end
  end
end
