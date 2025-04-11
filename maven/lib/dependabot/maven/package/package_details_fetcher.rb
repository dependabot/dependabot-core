# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/version"
require "dependabot/maven/requirement"
require "dependabot/maven/utils/auth_headers_finder"
require "sorbet-runtime"

module Dependabot
  module Maven
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        META_DATE_XML = T.let("maven-metadata.xml", String)
        REPOSITORY_TYPE = T.let("maven_repository", String)
        URL_KEY = T.let("url", String)
        AUTH_HEADERS_KEY = T.let("auth_headers", String)

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials

          @registry_urls = T.let(nil, T.nilable(T::Array[String]))
          @forbidden_urls = T.let([], T::Array[String])
          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @dependency_metadata = T.let({}, T::Hash[T.untyped, Nokogiri::XML::Document])
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @released_check = T.let({}, T::Hash[Version, T::Boolean])
          @auth_headers_finder = T.let(nil, T.nilable(Utils::AuthHeadersFinder))
          @dependency_parts = T.let([], T::Array[String])
          @dependency_classifier = T.let(nil, T.nilable(String))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials
        sig { returns(T::Array[T.untyped]) }
        attr_reader :forbidden_urls

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions
          version_details =
            repositories.flat_map do |repository_details|
              url = repository_details.fetch(URL_KEY)
              xml = dependency_metadata(repository_details)
              next [] if xml.nil?

              break xml.css("versions > version")
                       .select { |node| version_class.correct?(node.content) }
                       .map { |node| version_class.new(node.content) }
                       .map { |version| { version: version, source_url: url } }
            end

          raise PrivateSourceAuthenticationFailure, forbidden_urls.first if version_details.none? && forbidden_urls.any?

          version_details.sort_by { |details| details.fetch(:version) }
        end

        sig { params(version: Version).returns(T::Boolean) }
        def released?(version)
          @released_check[version] ||=
            repositories.any? do |repository_details|
              url = repository_details.fetch(URL_KEY)
              auth_headers = repository_details.fetch(AUTH_HEADERS_KEY)
              response = Dependabot::RegistryClient.head(
                url: dependency_files_url(url, version),
                headers: auth_headers
              )

              response.status < 400
            rescue Excon::Error::Socket, Excon::Error::Timeout,
                   Excon::Error::TooManyRedirects
              false
            rescue URI::InvalidURIError => e
              raise DependencyFileNotResolvable, e.message
            end
        end

        private

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def repositories
          return @repositories if @repositories

          @repositories = credentials_repository_details
          pom_repository_details.each do |repo|
            @repositories << repo unless @repositories.any? do |r|
              r[URL_KEY] == repo[URL_KEY]
            end
          end
          @repositories
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
          url = repository_details.fetch(URL_KEY)
          auth_headers = repository_details.fetch(AUTH_HEADERS_KEY)
          response = Dependabot::RegistryClient.get(
            url: dependency_metadata_url(url),
            headers: auth_headers
          )
          check_response(response, url)
          return unless response.status < 400

          Nokogiri::XML(response.body)
        rescue URI::InvalidURIError
          nil
        rescue Excon::Error::Socket, Excon::Error::Timeout,
               Excon::Error::TooManyRedirects => e
          handle_registry_error(url, e, response)
          nil
        end

        sig { params(response: Excon::Response, repository_url: String).void }
        def check_response(response, repository_url)
          return unless [401, 403].include?(response.status)
          return if @forbidden_urls.include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          @forbidden_urls << repository_url
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
              { URL_KEY => url, AUTH_HEADERS_KEY => {} }
            end
          @pom_repository_details
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          filename = dependency.requirements.first&.fetch(:file)
          dependency_files.find { |f| f.name == filename }
        end

        sig { params(repository_url: String).returns(String) }
        def dependency_metadata_url(repository_url)
          "#{dependency_artifact_id_url(repository_url)}/#{META_DATE_XML}"
        end

        sig { params(repository_url: String, version: Version).returns(String) }
        def dependency_files_url(repository_url, version)
          _, artifact_id = @dependency_parts
          url = dependency_artifact_id_url(repository_url)
          url += "/#{version}"
          url += "/#{artifact_id}-#{version}"
          url += dependency_classifier
          url += ".#{dependency_type}"
          url
        end

        sig { params(repository_url: String).returns(String) }
        def dependency_artifact_id_url(repository_url)
          group_path, artifact_id = dependency_parts

          # Example:
          # dependency: org.junit.jupiter:junit-jupiter-api
          # group_id: org.junit.jupiter
          # artifact_id: junit-jupiter-api
          # dependency_parts: ["org/junit/jupiter", "junit-jupiter-api"]
          # artifact_url: https://repo.maven.apache.org/maven2/org/junit/jupiter/junit-jupiter-api
          "#{repository_url}/#{group_path}/#{artifact_id}"
        end

        # Example:
        # dependency: org.junit.jupiter:junit-jupiter-api
        # group_id: org.junit.jupiter
        # artifact_id: junit-jupiter-api
        # dependency_parts: ["org/junit/jupiter", "junit-jupiter-api"]
        sig { returns(T::Array[String]) }
        def dependency_parts
          return @dependency_parts if @dependency_parts.any?

          group_id, artifact_id = dependency.name.split(":")
          group_id = group_id&.tr(".", "/")
          group_path = group_id&.tr(".", "/")
          @dependency_parts = [T.must(group_path), T.must(artifact_id)]
          @dependency_parts
        end

        sig { returns(String) }
        def dependency_type
          @dependency_type ||= T.let(dependency.requirements.first&.dig(:metadata, :packaging_type), T.nilable(String))
        end

        sig { returns(String) }
        def dependency_classifier
          return @dependency_classifier if @dependency_classifier

          classifier = dependency.requirements.first&.dig(:metadata, :classifier)
          @dependency_classifier = classifier.nil? ? "" : "-#{classifier}"
          @dependency_classifier
        end

        sig { returns(T::Array[T.untyped]) }
        def credentials_repository_details
          credentials
            .select { |cred| cred["type"] == REPOSITORY_TYPE && cred[URL_KEY] }
            .map do |cred|
              url_value = cred.fetch(URL_KEY).gsub(%r{/+$}, "")
              {
                URL_KEY => url_value,
                AUTH_HEADERS_KEY => auth_headers(url_value)
              }
            end
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

        sig do
          params(
            url: String,
            error: Excon::Error,
            response: T.nilable(Excon::Response)
          ).void
        end
        def handle_registry_error(url, error, response)
          return unless central_repo_urls.include?(url)

          response_status = response&.status || 0
          response_body = if response
                            "RegistryError: #{response.status} response status with body #{response.body}"
                          else
                            "RegistryError: #{error.message}"
                          end

          raise RegistryError.new(response_status, response_body)
        end
      end
    end
  end
end
