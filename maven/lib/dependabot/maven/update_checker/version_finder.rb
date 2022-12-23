# frozen_string_literal: true

require "nokogiri"
require "dependabot/update_checkers/version_filters"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/update_checker"
require "dependabot/maven/version"
require "dependabot/maven/requirement"
require "dependabot/maven/utils/auth_headers_finder"
require "dependabot/registry_client"

module Dependabot
  module Maven
    class UpdateChecker
      class VersionFinder
        TYPE_SUFFICES = %w(jre android java native_mt agp).freeze

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:,
                       raise_on_ignored: false)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
          @forbidden_urls      = []
          @dependency_metadata = {}
        end

        def latest_version_details
          possible_versions = versions

          possible_versions = filter_prereleases(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)

          possible_versions.reverse.find { |v| released?(v.fetch(:version)) }
        end

        def lowest_security_fix_version_details
          possible_versions = versions

          possible_versions = filter_prereleases(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(possible_versions,
                                                                                                    security_advisories)
          possible_versions = filter_ignored_versions(possible_versions)
          possible_versions = filter_lower_versions(possible_versions)

          possible_versions.find { |v| released?(v.fetch(:version)) }
        end

        def versions
          version_details =
            repositories.map do |repository_details|
              url = repository_details.fetch("url")
              xml = dependency_metadata(repository_details)
              next [] if xml.blank?

              break xml.css("versions > version").
                select { |node| version_class.correct?(node.content) }.
                map { |node| version_class.new(node.content) }.
                map { |version| { version: version, source_url: url } }
            end.flatten

          raise PrivateSourceAuthenticationFailure, forbidden_urls.first if version_details.none? && forbidden_urls.any?

          version_details.sort_by { |details| details.fetch(:version) }
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :forbidden_urls, :security_advisories

        def filter_prereleases(possible_versions)
          return possible_versions if wants_prerelease?

          possible_versions.reject { |v| v.fetch(:version).prerelease? }
        end

        def filter_date_based_versions(possible_versions)
          return possible_versions if wants_date_based_version?

          possible_versions.
            reject { |v| v.fetch(:version) > version_class.new(1900) }
        end

        def filter_version_types(possible_versions)
          possible_versions.
            select { |v| matches_dependency_version_type?(v.fetch(:version)) }
        end

        def filter_ignored_versions(possible_versions)
          filtered = possible_versions

          ignored_versions.each do |req|
            ignore_requirements = Maven::Requirement.requirements_array(req)
            filtered =
              filtered.
              reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v.fetch(:version)) } }
          end

          if @raise_on_ignored && filter_lower_versions(filtered).empty? &&
             filter_lower_versions(possible_versions).any?
            raise AllVersionsIgnored
          end

          filtered
        end

        def filter_lower_versions(possible_versions)
          return possible_versions unless dependency.numeric_version

          possible_versions.select do |v|
            v.fetch(:version) > dependency.numeric_version
          end
        end

        def wants_prerelease?
          return false unless dependency.numeric_version

          dependency.numeric_version.prerelease?
        end

        def wants_date_based_version?
          return false unless dependency.numeric_version

          dependency.numeric_version >= version_class.new(100)
        end

        def released?(version)
          @released_check ||= {}
          return @released_check[version] if @released_check.key?(version)

          @released_check[version] =
            repositories.any? do |repository_details|
              url = repository_details.fetch("url")
              response = Dependabot::RegistryClient.head(
                url: dependency_files_url(url, version),
                headers: repository_details.fetch("auth_headers")
              )

              response.status < 400
            rescue Excon::Error::Socket, Excon::Error::Timeout,
                   Excon::Error::TooManyRedirects
              false
            rescue URI::InvalidURIError => e
              raise DependencyFileNotResolvable, e.message
            end
        end

        def dependency_metadata(repository_details)
          repository_key = repository_details.hash
          return @dependency_metadata[repository_key] if @dependency_metadata.key?(repository_key)

          @dependency_metadata[repository_key] = fetch_dependency_metadata(repository_details)
        end

        def fetch_dependency_metadata(repository_details)
          response = Dependabot::RegistryClient.get(
            url: dependency_metadata_url(repository_details.fetch("url")),
            headers: repository_details.fetch("auth_headers")
          )
          check_response(response, repository_details.fetch("url"))
          return unless response.status < 400

          Nokogiri::XML(response.body)
        rescue URI::InvalidURIError
          nil
        rescue Excon::Error::Socket, Excon::Error::Timeout,
               Excon::Error::TooManyRedirects
          raise if central_repo_urls.include?(repository_details["url"])

          nil
        end

        def check_response(response, repository_url)
          return unless [401, 403].include?(response.status)
          return if @forbidden_urls.include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          @forbidden_urls << repository_url
        end

        def repositories
          return @repositories if defined?(@repositories)

          @repositories = credentials_repository_details
          pom_repository_details.each do |repo|
            @repositories << repo unless @repositories.any? { |r| r["url"] == repo["url"] }
          end
          @repositories
        end

        def repository_finder
          @repository_finder ||=
            Maven::FileParser::RepositoriesFinder.new(
              pom_fetcher: Maven::FileParser::PomFetcher.new(dependency_files: dependency_files),
              dependency_files: dependency_files,
              credentials: credentials
            )
        end

        def pom_repository_details
          @pom_repository_details ||=
            repository_finder.
            repository_urls(pom: pom).
            map do |url|
              { "url" => url, "auth_headers" => {} }
            end
        end

        def credentials_repository_details
          credentials.
            select { |cred| cred["type"] == "maven_repository" }.
            map do |cred|
              {
                "url" => cred.fetch("url").gsub(%r{/+$}, ""),
                "auth_headers" => auth_headers(cred.fetch("url").gsub(%r{/+$}, ""))
              }
            end
        end

        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type = dependency.version.
                         gsub("native-mt", "native_mt").
                         split(/[.\-]/).
                         find do |type|
                           TYPE_SUFFICES.find { |s| type.include?(s) }
                         end

          version_type = comparison_version.to_s.
                         gsub("native-mt", "native_mt").
                         split(/[.\-]/).
                         find do |type|
                           TYPE_SUFFICES.find { |s| type.include?(s) }
                         end

          current_type == version_type
        end

        def pom
          filename = dependency.requirements.first.fetch(:file)
          dependency_files.find { |f| f.name == filename }
        end

        def dependency_metadata_url(repository_url)
          group_id, artifact_id, _classifier = dependency.name.split(":")

          "#{repository_url}/" \
            "#{group_id.tr('.', '/')}/" \
            "#{artifact_id}/" \
            "maven-metadata.xml"
        end

        def dependency_files_url(repository_url, version)
          group_id, artifact_id, classifier = dependency.name.split(":")
          type = dependency.requirements.first.
                 dig(:metadata, :packaging_type)

          actual_classifier = classifier.nil? ? "" : "-#{classifier}"
          "#{repository_url}/" \
            "#{group_id.tr('.', '/')}/" \
            "#{artifact_id}/" \
            "#{version}/" \
            "#{artifact_id}-#{version}#{actual_classifier}.#{type}"
        end

        def version_class
          Maven::Version
        end

        def central_repo_urls
          central_url_without_protocol = repository_finder.central_repo_url.gsub(%r{^.*://}, "")

          %w(http:// https://).map { |p| p + central_url_without_protocol }
        end

        def auth_headers_finder
          @auth_headers_finder ||= Utils::AuthHeadersFinder.new(credentials)
        end

        def auth_headers(maven_repo_url)
          auth_headers_finder.auth_headers(maven_repo_url)
        end
      end
    end
  end
end
