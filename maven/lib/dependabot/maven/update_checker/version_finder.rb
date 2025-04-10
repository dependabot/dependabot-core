# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "dependabot/update_checkers/version_filters"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/update_checker"
require "dependabot/maven/version"
require "dependabot/maven/requirement"
require "dependabot/maven/utils/auth_headers_finder"
require "dependabot/registry_client"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
      class VersionFinder
        extend T::Sig

        TYPE_SUFFICES = %w(jre android java native_mt agp).freeze

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
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:,
                       raise_on_ignored: false)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
          @forbidden_urls      = T.let([], T::Array[String])
          @dependency_metadata = T.let({}, T::Hash[T.untyped, Nokogiri::XML::Document])
          @auth_headers_finder = T.let(nil, T.nilable(Utils::AuthHeadersFinder))
          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @released_check = T.let({}, T::Hash[Version, T::Boolean])
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def latest_version_details
          possible_versions = versions

          possible_versions = filter_prereleases(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)

          possible_versions.reverse.find { |v| released?(v.fetch(:version)) }
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
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

        sig { returns(T::Array[T.untyped]) }
        def versions
          version_details =
            repositories.map do |repository_details|
              url = repository_details.fetch("url")
              xml = dependency_metadata(repository_details)
              next [] if xml.nil?

              break xml.css("versions > version")
                       .select { |node| version_class.correct?(node.content) }
                       .map { |node| version_class.new(node.content) }
                       .map { |version| { version: version, source_url: url } }
            end.flatten

          raise PrivateSourceAuthenticationFailure, forbidden_urls.first if version_details.none? && forbidden_urls.any?

          version_details.sort_by { |details| details.fetch(:version) }
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions
        sig { returns(T::Array[String]) }
        attr_reader :forbidden_urls
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_prereleases(possible_versions)
          return possible_versions if wants_prerelease?

          filtered = possible_versions.reject { |v| v.fetch(:version).prerelease? }
          if possible_versions.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_versions.count - filtered.count} pre-release versions")
          end
          filtered
        end

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_date_based_versions(possible_versions)
          return possible_versions if wants_date_based_version?

          filtered = possible_versions.reject { |v| v.fetch(:version) > version_class.new(1900) }
          if possible_versions.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_versions.count - filtered.count} date-based versions")
          end
          filtered
        end

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_version_types(possible_versions)
          filtered = possible_versions.select { |v| matches_dependency_version_type?(v.fetch(:version)) }
          if possible_versions.count > filtered.count
            diff = possible_versions.count - filtered.count
            classifier = dependency.version&.split(/[.\-]/)&.last
            Dependabot.logger.info("Filtered out #{diff} non-#{classifier} classifier versions")
          end
          filtered
        end

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_ignored_versions(possible_versions)
          filtered = possible_versions

          ignored_versions.each do |req|
            ignore_requirements = Maven::Requirement.requirements_array(req)
            filtered =
              filtered
              .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v.fetch(:version)) } }
          end

          if @raise_on_ignored && filter_lower_versions(filtered).empty? &&
             filter_lower_versions(possible_versions).any?
            raise AllVersionsIgnored
          end

          if possible_versions.count > filtered.count
            diff = possible_versions.count - filtered.count
            Dependabot.logger.info("Filtered out #{diff} ignored versions")
          end

          filtered
        end

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_lower_versions(possible_versions)
          return possible_versions unless dependency.numeric_version

          possible_versions.select do |v|
            v.fetch(:version) > dependency.numeric_version
          end
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return false unless dependency.numeric_version

          dependency.numeric_version&.prerelease? || false
        end

        sig { returns(T::Boolean) }
        def wants_date_based_version?
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version) >= version_class.new(100)
        end

        sig { params(version: Version).returns(T::Boolean) }
        def released?(version)
          @released_check[version] ||=
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

        sig { params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::XML::Document)) }
        def dependency_metadata(repository_details)
          repository_key = repository_details.hash
          return @dependency_metadata[repository_key] if @dependency_metadata.key?(repository_key)

          xml_document = fetch_dependency_metadata(repository_details)

          @dependency_metadata[repository_key] ||= xml_document if xml_document
          @dependency_metadata[repository_key]
        end

        sig { params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::XML::Document)) }
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
               Excon::Error::TooManyRedirects => e

          if central_repo_urls.include?(repository_details["url"])
            response_status = response&.status || 0
            response_body = if response
                              "RegistryError: #{response.status} response status with body #{response.body}"
                            else
                              "RegistryError: #{e.message}"
                            end

            raise RegistryError.new(response_status, response_body)
          end

          nil
        end

        sig { params(response: Excon::Response, repository_url: String).void }
        def check_response(response, repository_url)
          return unless [401, 403].include?(response.status)
          return if @forbidden_urls.include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          @forbidden_urls << repository_url
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def repositories
          return @repositories if @repositories

          @repositories = credentials_repository_details
          pom_repository_details.each do |repo|
            @repositories << repo unless @repositories.any? { |r| r["url"] == repo["url"] }
          end
          @repositories
        end

        sig { returns(Maven::FileParser::RepositoriesFinder) }
        def repository_finder
          return @repository_finder if @repository_finder

          @repository_finder =
            Maven::FileParser::RepositoriesFinder.new(
              pom_fetcher: Maven::FileParser::PomFetcher.new(dependency_files: dependency_files),
              dependency_files: dependency_files,
              credentials: credentials
            )
          @repository_finder
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def pom_repository_details
          return @pom_repository_details if @pom_repository_details

          @pom_repository_details =
            repository_finder
            .repository_urls(pom: pom)
            .map do |url|
              { "url" => url, "auth_headers" => {} }
            end
          @pom_repository_details
        end

        sig { returns(T::Array[T.untyped]) }
        def credentials_repository_details
          credentials
            .select { |cred| cred["type"] == "maven_repository" && cred["url"] }
            .map do |cred|
              {
                "url" => cred.fetch("url").gsub(%r{/+$}, ""),
                "auth_headers" => auth_headers(cred.fetch("url").gsub(%r{/+$}, ""))
              }
            end
        end

        sig { params(comparison_version: Version).returns(T::Boolean) }
        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type = dependency.version
                                   &.gsub("native-mt", "native_mt")
                                   &.split(/[.\-]/)
                                   &.find do |type|
            TYPE_SUFFICES.find { |s| type.include?(s) }
          end

          version_type = comparison_version.to_s
                                           .gsub("native-mt", "native_mt")
                                           .split(/[.\-]/)
                                           .find do |type|
            TYPE_SUFFICES.find { |s| type.include?(s) }
          end

          current_type == version_type
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          filename = dependency.requirements.first&.fetch(:file)
          dependency_files.find { |f| f.name == filename }
        end

        sig { params(repository_url: String).returns(String) }
        def dependency_metadata_url(repository_url)
          group_id, artifact_id = dependency.name.split(":")

          "#{repository_url}/" \
            "#{group_id&.tr('.', '/')}/" \
            "#{artifact_id}/" \
            "maven-metadata.xml"
        end

        sig { params(repository_url: String, version: Version).returns(String) }
        def dependency_files_url(repository_url, version)
          group_id, artifact_id = dependency.name.split(":")
          type = dependency.requirements.first&.dig(:metadata, :packaging_type)
          classifier = dependency.requirements.first&.dig(:metadata, :classifier)

          actual_classifier = classifier.nil? ? "" : "-#{classifier}"
          "#{repository_url}/" \
            "#{group_id&.tr('.', '/')}/" \
            "#{artifact_id}/" \
            "#{version}/" \
            "#{artifact_id}-#{version}#{actual_classifier}.#{type}"
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T::Array[String]) }
        def central_repo_urls
          central_url_without_protocol = repository_finder.central_repo_url.gsub(%r{^.*://}, "")

          %w(http:// https://).map { |p| p + central_url_without_protocol }
        end

        sig { returns(Utils::AuthHeadersFinder) }
        def auth_headers_finder
          return @auth_headers_finder if @auth_headers_finder

          @auth_headers_finder = Utils::AuthHeadersFinder.new(credentials)
          @auth_headers_finder
        end

        sig { params(maven_repo_url: String).returns(T::Hash[String, String]) }
        def auth_headers(maven_repo_url)
          auth_headers_finder.auth_headers(maven_repo_url)
        end
      end
    end
  end
end
