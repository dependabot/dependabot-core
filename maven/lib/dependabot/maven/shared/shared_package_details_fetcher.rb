# typed: strict
# frozen_string_literal: true

require "time"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/maven/utils/auth_headers_finder"

module Dependabot
  module Maven
    module Shared
      class SharedPackageDetailsFetcher
        extend T::Sig
        extend T::Helpers

        abstract!

        MAVEN_METADATA_XML = T.let("maven-metadata.xml", String)
        REPOSITORY_TYPE = T.let("maven_repository", String)
        URL_KEY = T.let("url", String)
        AUTH_HEADERS_KEY = T.let("auth_headers", String)
        DEFAULT_CENTRAL_REPO_URL = T.let("https://repo.maven.apache.org/maven2", String)

        sig { abstract.returns(Dependabot::Dependency) }
        def dependency; end

        sig { abstract.returns(T::Array[Dependabot::Credential]) }
        def credentials; end

        # Subclasses must define how repositories are assembled.
        # Typically: credentials_repository_details + ecosystem-specific repos.
        sig { abstract.returns(T::Array[T::Hash[String, T.untyped]]) }
        def repositories; end

        # -- URL Construction --

        # Splits the dependency name (group_id:artifact_id) into [group_path, artifact_id].
        #
        # Example:
        #   "com.google.guava:guava" → ["com/google/guava", "guava"]
        sig { returns([String, String]) }
        def dependency_parts
          @dependency_parts = T.let(@dependency_parts, T.nilable([String, String]))
          return @dependency_parts if @dependency_parts

          group_id, artifact_id = dependency.name.split(":")
          group_path = T.must(group_id).tr(".", "/")
          @dependency_parts = [group_path, T.must(artifact_id)]
        end

        # Base URL for a dependency: repo_url/group_path/artifact_id
        #
        # Example:
        #   "https://repo.maven.apache.org/maven2/com/google/guava/guava"
        sig { params(repository_url: String).returns(String) }
        def dependency_base_url(repository_url)
          group_path, artifact_id = dependency_parts
          "#{repository_url}/#{group_path}/#{artifact_id}"
        end

        # URL for maven-metadata.xml
        sig { params(repository_url: String).returns(String) }
        def dependency_metadata_url(repository_url)
          "#{dependency_base_url(repository_url)}/#{MAVEN_METADATA_XML}"
        end

        # URL for a specific artifact file (JAR/AAR/etc).
        #
        # Example:
        #   "https://repo.maven.apache.org/maven2/com/google/guava/guava/23.6-jre/guava-23.6-jre.jar"
        sig { params(repository_url: String, version: Dependabot::Version).returns(String) }
        def dependency_files_url(repository_url, version)
          _, artifact_id = dependency_parts
          base_url = dependency_base_url(repository_url)
          type = dependency.requirements.first&.dig(:metadata, :packaging_type) || "jar"
          classifier = dependency.requirements.first&.dig(:metadata, :classifier)
          actual_classifier = classifier.nil? ? "" : "-#{classifier}"

          "#{base_url}/#{version}/#{artifact_id}-#{version}#{actual_classifier}.#{type}"
        end

        # URL for the POM file of a specific version.
        # Every published Maven artifact has a .pom file regardless of packaging type.
        sig { params(repository_url: String, version: Dependabot::Version).returns(String) }
        def dependency_pom_url(repository_url, version)
          _, artifact_id = dependency_parts
          base_url = dependency_base_url(repository_url)
          "#{base_url}/#{version}/#{artifact_id}-#{version}.pom"
        end

        # -- Metadata Fetching (XML) --

        # Fetches and parses maven-metadata.xml from a repository.
        sig { params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::XML::Document)) }
        def fetch_dependency_metadata(repository_details)
          url = repository_details.fetch(URL_KEY)
          headers = repository_details.fetch(AUTH_HEADERS_KEY)
          response = Dependabot::RegistryClient.get(
            url: dependency_metadata_url(url),
            headers: headers
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

        # Extracts version objects from a parsed maven-metadata.xml document.
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

        # -- Metadata Fetching (HTML directory listing) --

        # Fetches an HTML directory listing page from a repository.
        sig do
          params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::HTML::Document))
        end
        def fetch_dependency_metadata_from_html(repository_details)
          url = repository_details.fetch(URL_KEY)
          headers = repository_details.fetch(AUTH_HEADERS_KEY)
          response = Dependabot::RegistryClient.get(
            url: dependency_base_url(url),
            headers: headers
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

        # Parses release dates from an HTML directory listing page.
        sig do
          params(html_doc: Nokogiri::HTML::Document)
            .returns(T::Hash[String, T::Hash[Symbol, T.untyped]])
        end
        def extract_version_details_from_html(html_doc)
          versions_detail_hash = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

          html_doc.css("a[title]").each do |link|
            version_string = link["title"]
            version = version_string.gsub(%r{/$}, "")

            raw_date_text = link.next.text.strip.split("\n").last.strip

            release_date = begin
              Time.parse(raw_date_text)
            rescue StandardError
              nil
            end

            next unless version && version_class.correct?(version)

            versions_detail_hash[version] = { release_date: release_date }
          end

          versions_detail_hash
        end

        # -- Response Checking & Error Handling --

        # Tracks forbidden URLs when receiving 401/403 responses (except for central repo).
        sig { params(response: Excon::Response, repository_url: String).void }
        def check_response(response, repository_url)
          return unless [401, 403].include?(response.status)
          return if forbidden_urls.include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          forbidden_urls << repository_url
        end

        # Raises RegistryError for failures hitting the central repo.
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

        # -- Version Aggregation --

        # Aggregates version details from XML metadata and enriches with
        # release dates from HTML directory listings. Returns a sorted array
        # of version detail hashes.
        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions
          @version_details = T.let(@version_details, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
          return @version_details if @version_details

          @version_details = versions_details_from_xml

          begin
            versions_details_hash = versions_details_hash_from_html if @version_details.any?

            if versions_details_hash
              @version_details = @version_details.map do |vd|
                html_details = versions_details_hash[vd[:version].to_s]

                next vd unless html_details

                release_date = html_details[:release_date]

                next vd unless release_date

                vd.merge(
                  release_date: html_details[:release_date],
                  source_url: vd[:source_url]
                )
              end
            end
          rescue StandardError => e
            Dependabot.logger.error(
              "Error fetching version details from HTML: #{e.message}"
            )
          end

          @version_details = @version_details.sort_by { |d| d.fetch(:version) }
          @version_details
        end

        # Fetches version details from maven-metadata.xml across all repositories.
        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def versions_details_from_xml
          forbidden_urls.clear
          version_details = repositories.flat_map do |repository_details|
            url = repository_details.fetch(URL_KEY)
            xml = dependency_metadata(repository_details)
            next [] if xml.nil?

            extract_metadata_from_xml(xml, url)
          end

          raise PrivateSourceAuthenticationFailure, forbidden_urls.first if version_details.none? && forbidden_urls.any?

          version_details
        end

        # Fetches version details (release dates) from HTML directory listings.
        sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def versions_details_hash_from_html
          forbidden_urls.clear

          versions_detail_hash = T.let(
            {}, T::Hash[String, T::Hash[Symbol, T.untyped]]
          )
          repositories.each do |repository_details|
            html = dependency_metadata_from_html(repository_details)
            next if html.nil?

            versions_detail_hash = extract_version_details_from_html(html)
            break if versions_detail_hash.any?
          end

          if versions_detail_hash.any? && forbidden_urls.any?
            raise PrivateSourceAuthenticationFailure,
                  forbidden_urls.first
          end

          versions_detail_hash
        end

        # -- Release Check --

        # Checks whether a specific version of the dependency has been published
        # by issuing HEAD requests to each repository.
        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def released?(version)
          @released_check = T.let(@released_check, T.nilable(T::Hash[Dependabot::Version, T::Boolean]))
          @released_check ||= {}
          return T.must(@released_check[version]) if @released_check.key?(version)

          @released_check[version] =
            repositories.any? do |repository_details|
              url = repository_details.fetch(URL_KEY)
              headers = repository_details.fetch(AUTH_HEADERS_KEY)
              response = Dependabot::RegistryClient.head(
                url: dependency_files_url(url, version),
                headers: headers
              )
              next true if response.status < 400

              # When the artifact file returns 404, fall back to checking the .pom file.
              # This handles artifacts with non-jar packaging (e.g., aar, bundle) where
              # the consumer POM omits <type>, causing the parser to default to "jar".
              # Only fall back when there's no classifier (classifier artifacts are specific).
              next false unless response.status == 404
              next false if dependency.requirements.first&.dig(:metadata, :classifier)

              pom_response = Dependabot::RegistryClient.head(
                url: dependency_pom_url(url, version),
                headers: headers
              )
              pom_response.status < 400
            rescue Excon::Error::Socket, Excon::Error::Timeout,
                   Excon::Error::TooManyRedirects
              false
            rescue URI::InvalidURIError => e
              raise DependencyFileNotResolvable, e.message
            end
        end

        # -- Credential & Repository Helpers --

        # Builds repository details from credentials of type "maven_repository".
        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
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

        # The default central repo URL. Subclasses may override (e.g., if credentials
        # provide a replacement base repo).
        sig { returns(String) }
        def central_repo_url
          DEFAULT_CENTRAL_REPO_URL
        end

        # Both HTTP and HTTPS variants of the central repo URL, for comparison.
        sig { returns(T::Array[String]) }
        def central_repo_urls
          central_url_without_protocol = central_repo_url.gsub(%r{^.*://}, "")
          %w(http:// https://).map { |p| p + central_url_without_protocol }
        end

        sig { returns(T::Array[String]) }
        def forbidden_urls
          @forbidden_urls ||= T.let([], T.nilable(T::Array[String]))
        end

        # -- Auth --

        sig { params(maven_repo_url: String).returns(T::Hash[String, String]) }
        def auth_headers(maven_repo_url)
          auth_headers_finder.auth_headers(maven_repo_url)
        end

        sig { returns(Utils::AuthHeadersFinder) }
        def auth_headers_finder
          @auth_headers_finder ||= T.let(Utils::AuthHeadersFinder.new(credentials), T.nilable(Utils::AuthHeadersFinder))
        end

        # -- Metadata Caching --

        # Fetches and caches XML metadata per repository.
        sig { params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::XML::Document)) }
        def dependency_metadata(repository_details)
          @dependency_metadata = T.let(
            @dependency_metadata, T.nilable(T::Hash[T.untyped, Nokogiri::XML::Document])
          )
          @dependency_metadata ||= {}
          repository_key = repository_details.hash
          return @dependency_metadata[repository_key] if @dependency_metadata.key?(repository_key)

          xml_document = fetch_dependency_metadata(repository_details)
          @dependency_metadata[repository_key] ||= xml_document if xml_document
          @dependency_metadata[repository_key]
        end

        # Fetches and caches HTML metadata per repository.
        sig { params(repository_details: T::Hash[String, T.untyped]).returns(T.nilable(Nokogiri::HTML::Document)) }
        def dependency_metadata_from_html(repository_details)
          @dependency_metadata_from_html = T.let(
            @dependency_metadata_from_html, T.nilable(T::Hash[T.untyped, Nokogiri::HTML::Document])
          )
          @dependency_metadata_from_html ||= {}
          repository_key = repository_details.hash
          return @dependency_metadata_from_html[repository_key] if @dependency_metadata_from_html.key?(repository_key)

          html_document = fetch_dependency_metadata_from_html(repository_details)
          @dependency_metadata_from_html[repository_key] ||= html_document if html_document
          @dependency_metadata_from_html[repository_key]
        end

        # -- Version Class --

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end
      end
    end
  end
end
