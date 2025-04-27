# typed: strict
# frozen_string_literal: true

require "time"
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
        def initialize(dependency:, dependency_files:, credentials:) # rubocop:disable Metrics/AbcSize
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials

          @forbidden_urls = T.let([], T::Array[String])
          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @dependency_metadata = T.let({}, T::Hash[T.untyped, Nokogiri::XML::Document])
          @dependency_metadata_from_html = T.let({}, T::Hash[T.untyped, Nokogiri::HTML::Document])
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @released_check = T.let({}, T::Hash[Dependabot::Version, T::Boolean])
          @auth_headers_finder = T.let(nil, T.nilable(Utils::AuthHeadersFinder))
          @dependency_parts = T.let(nil, T.nilable([String, String]))
          @version_details = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials
        sig { returns(T::Array[T.untyped]) }
        attr_reader :forbidden_urls

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          return @package_details if @package_details

          releases = versions.map do |version_details|
            Dependabot::Package::PackageRelease.new(
              version: version_details.fetch(:version),
              released_at: version_details.fetch(:release_date, nil),
              url: version_details.fetch(:source_url)
            )
          end

          @package_details = Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: releases
          )

          @package_details
        end

        sig { returns(T::Array[T.untyped]) }
        def releases
          fetch.releases
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def released?(version)
          released_check?(version)
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions
          return @version_details if @version_details

          @version_details = versions_details_from_xml

          begin
            versions_details_hash = versions_details_hash_from_html if @version_details.any?

            if versions_details_hash
              @version_details = @version_details.map do |version_details|
                version = version_details[:version].to_s
                version_details_hash = versions_details_hash[version]

                next version_details unless version_details_hash

                release_date = version_details_hash[:release_date]

                next version_details unless release_date

                version_details.merge(
                  release_date: version_details_hash[:release_date],
                  source_url: version_details[:source_url]
                )
              end
            end
          rescue StandardError => e
            Dependabot.logger.error("Error fetching version details from HTML: #{e.message}")
          end

          @version_details = @version_details.sort_by { |details| details.fetch(:version) }
          @version_details
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions_details_from_xml
          forbidden_urls.clear
          version_details = repositories.flat_map do |repository_details|
            url = repository_details.fetch(URL_KEY)
            xml = dependency_metadata(repository_details)
            next [] if xml.nil?

            break extract_metadata_from_xml(xml, url)
          end

          raise PrivateSourceAuthenticationFailure, forbidden_urls.first if version_details.none? && forbidden_urls.any?

          version_details
        end

        sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def versions_details_hash_from_html
          forbidden_urls.clear

          # Iterate over repositories and fetch the first valid result
          versions_detail_hash = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
          repositories.each do |repository_details|
            html = dependency_metadata_from_html(repository_details)

            # Skip if no HTML data is found
            next if html.nil?

            # Break and return result from the first valid HTML
            versions_detail_hash = extract_version_details_from_html(html)

            break if versions_detail_hash.any?
          end

          # If no version details were found, but there are forbidden URLs, raise an error
          if versions_detail_hash.any? && forbidden_urls.any?
            raise PrivateSourceAuthenticationFailure,
                  forbidden_urls.first
          end

          # Return the populated version details hash (may be empty if no valid repositories)
          versions_detail_hash
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def released_check?(version)
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

        # Extracts version details from the HTML document.
        sig do
          params(html_doc: Nokogiri::HTML::Document)
            .returns(T::Hash[String, T::Hash[Symbol, T.untyped]])
        end
        def extract_version_details_from_html(html_doc)
          versions_detail_hash = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

          html_doc.css("a[title]").each do |link|
            version_string = link["title"]
            version = version_string.gsub(%r{/$}, "") # Remove trailing slash

            # Release date should be located after the version, and it is within the same <pre> block
            raw_date_text = link.next.text.strip.split("\n").last.strip # Extract the last part of the text

            # Parse the date and time properly (YYYY-MM-DD HH:MM)
            release_date = begin
              Time.parse(raw_date_text)
            rescue StandardError
              nil
            end

            next unless version && version_class.correct?(version)

            versions_detail_hash[version] = {
              release_date: release_date
            }
          end
          versions_detail_hash
        end

        # Extracts version details from the XML document.
        sig do
          params(
            xml: Nokogiri::XML::Document,
            url: String
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def extract_metadata_from_xml(xml, url)
          xml.css("versions > version")
             .select { |node| version_class.correct?(node.content) }
             .map { |node| version_class.new(node.content) }
             .map { |version| { version: version, source_url: url } }
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

        sig { params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::HTML::Document)) }
        def dependency_metadata_from_html(repository_details)
          repository_key = repository_details.hash
          return @dependency_metadata_from_html[repository_key] if @dependency_metadata_from_html.key?(repository_key)

          html_document = fetch_dependency_metadata_from_html(repository_details)

          @dependency_metadata_from_html[repository_key] ||= html_document if html_document
          @dependency_metadata_from_html[repository_key]
        end

        sig { params(response: Excon::Response, repository_url: String).void }
        def check_response(response, repository_url)
          return unless [401, 403].include?(response.status)
          return if @forbidden_urls.include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          @forbidden_urls << repository_url
        end

        sig do
          params(
            repository_details: T::Hash[String, T.untyped]
          ).returns(T.nilable(Nokogiri::HTML::Document))
        end
        def fetch_dependency_metadata_from_html(repository_details)
          url = repository_details.fetch(URL_KEY)
          auth_headers = repository_details.fetch(AUTH_HEADERS_KEY)
          response = Dependabot::RegistryClient.get(
            url: dependency_base_url(url),
            headers: auth_headers
          )
          check_response(response, url)
          return unless response.status < 400

          Nokogiri::HTML(response.body)
        rescue URI::InvalidURIError
          nil
        rescue Excon::Error::Socket, Excon::Error::Timeout,
               Excon::Error::TooManyRedirects => e
          handle_registry_error(url, e, response)
          nil
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

        # Returns the repository details for the POM file.
        # Example:
        #  repository_url: https://repo.maven.apache.org/maven2
        #  returns: [{ "url" => "https://repo.maven.apache.org/maven2", "auth_headers" => {} }]
        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def pom_repository_details
          return @pom_repository_details if @pom_repository_details

          @pom_repository_details =
            repository_finder
            .repository_urls(pom: T.must(pom))
            .map do |url|
              { URL_KEY => url, AUTH_HEADERS_KEY => {} }
            end
          @pom_repository_details
        end

        # Returns the POM file for the dependency, if it exists.
        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          filename = dependency.requirements.first&.fetch(:file)
          dependency_files.find { |f| f.name == filename }
        end

        # Constructs the URL for the dependency's metadata file (maven-metadata.xml).
        #
        # Example:
        #   repository_url: https://repo.maven.apache.org/maven2
        #   returns: https://repo.maven.apache.org/maven2/com/google/guava/guava/maven-metadata.xml
        sig { params(repository_url: String).returns(String) }
        def dependency_metadata_url(repository_url)
          "#{dependency_base_url(repository_url)}/#{META_DATE_XML}"
        end

        # Constructs the URL for the dependency files, including version and artifact information.
        #
        # Example:
        #   repository_url: https://repo.maven.apache.org/maven2
        #   version: 23.6-jre
        #   artifact_id: guava
        #   group_id: com.google.guava
        #   classifier: nil
        #   type: jar
        #   returns: https://repo.maven.apache.org/maven2/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar
        #            https://repo.maven.apache.org/maven2/com/google/guava/guava/23.7-jre/-23.7-jre.jar
        sig { params(repository_url: String, version: Dependabot::Version).returns(String) }
        def dependency_files_url(repository_url, version)
          _, artifact_id = dependency_parts
          base_url = dependency_base_url(repository_url)
          type = dependency.requirements.first&.dig(:metadata, :packaging_type)
          classifier = dependency.requirements.first&.dig(:metadata, :classifier)
          actual_classifier = classifier.nil? ? "" : "-#{classifier}"

          "#{base_url}/#{version}/" \
            "#{artifact_id}-#{version}#{actual_classifier}.#{type}"
        end

        #           # Constructs the full URL by combining the repository URL, group path, and artifact ID
        #
        # Example:
        #   repository_url: https://repo.maven.apache.org/maven2
        #   group_path: com/google/guava
        #   artifact_id: guava
        #   returns: https://repo.maven.apache.org/maven2/com/google/guava/guava
        sig { params(repository_url: String).returns(String) }
        def dependency_base_url(repository_url)
          group_path, artifact_id = dependency_parts

          "#{repository_url}/#{group_path}/#{artifact_id}"
        end

        # Splits the dependency name into its group path and artifact ID.
        #
        # Example:
        #   dependency.name: com.google.guava:guava
        #   returns: ["com/google/guava", "guava"]
        sig { returns(T.nilable([String, String])) }
        def dependency_parts
          return @dependency_parts if @dependency_parts

          group_id, artifact_id = dependency.name.split(":")
          group_path = group_id&.tr(".", "/")
          @dependency_parts = [T.must(group_path), T.must(artifact_id)]
          @dependency_parts
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
