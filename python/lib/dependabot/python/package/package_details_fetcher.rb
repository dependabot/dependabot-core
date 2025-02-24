# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_release"
require "dependabot/python/package/package_details"
require "dependabot/python/package/package_registry_finder"

# Stores metadata for a package, including all its available versions
module Dependabot
  module Python
    module Package
      CREDENTIALS_USERNAME = "username"
      CREDENTIALS_PASSWORD = "password"

      APPLICATION_JSON = "application/json"
      APPLICATION_TEXT = "text/html"
      CPYTHON = "cpython"
      PYTHON = "python"
      UNKNOWN = "unknown"

      MAIN_PYPI_INDEXES = %w(
        https://pypi.python.org/simple/
        https://pypi.org/simple/
      ).freeze
      VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials

          @registry_urls = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(Dependabot::Python::Package::PackageDetails) }
        def fetch
          package_releases = registry_urls
                             .select { |index_url| validate_index(index_url) } # Ensure only valid URLs
                             .flat_map do |index_url|
            fetch_from_registry(index_url) || [] # Ensure it always returns an array
            rescue Excon::Error::Timeout, Excon::Error::Socket
              raise if MAIN_PYPI_INDEXES.include?(index_url)

              raise PrivateSourceTimedOut, sanitized_url(index_url)
            rescue URI::InvalidURIError
              raise DependencyFileNotResolvable, "Invalid URL: #{sanitized_url(index_url)}"
          end

          Dependabot::Python::Package::PackageDetails.new(
            dependency: dependency,
            releases: package_releases.reverse.uniq(&:version)
          )
        end

        private

        sig do
          params(index_url: String)
            .returns(T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
        end
        def fetch_from_registry(index_url)
          if Dependabot::Experiments.enabled?(:enable_cooldown_for_python)
            metadata = fetch_from_json_registry(index_url)

            return metadata if metadata&.any?

            Dependabot.logger.warn("No valid versions found via JSON API. Falling back to HTML.")
          end
          fetch_from_html_registry(index_url)
        rescue StandardError => e
          Dependabot.logger.warn("Unexpected error in JSON fetch: #{e.message}. Falling back to HTML.")
          fetch_from_html_registry(index_url)
        end

        # Example JSON Response Format:
        #
        # {
        #   "info": {
        #     "name": "requests",
        #     "summary": "Python HTTP for Humans.",
        #     "author": "Kenneth Reitz",
        #     "license": "Apache-2.0"
        #   },
        #   "releases": {
        #     "2.32.3": [
        #       {
        #         "filename": "requests-2.32.3-py3-none-any.whl",
        #         "version": "2.32.3",
        #         "requires_python": ">=3.8",
        #         "yanked": false,
        #         "url": "https://files.pythonhosted.org/packages/f9/9b/335f9764261e915ed497fcdeb11df5dfd6f7bf257d4a6a2a686d80da4d54/requests-2.32.3-py3-none-any.whl"
        #       },
        #       {
        #         "filename": "requests-2.32.3.tar.gz",
        #         "version": "2.32.3",
        #         "requires_python": ">=3.8",
        #         "yanked": false,
        #         "url": "https://files.pythonhosted.org/packages/63/70/2bf7780ad2d390a8d301ad0b550f1581eadbd9a20f896afe06353c2a2913/requests-2.32.3.tar.gz"
        #       }
        #     ],
        #     "2.27.0": [
        #       {
        #         "filename": "requests-2.27.0-py2.py3-none-any.whl",
        #         "version": "2.27.0",
        #         "requires_python": ">=2.7, !=3.0.*, !=3.1.*, !=3.2.*, !=3.3.*, !=3.4.*, !=3.5.*",
        #         "yanked": false,
        #         "url": "https://files.pythonhosted.org/packages/47/01/f420e7add78110940639a958e5af0e3f8e07a8a8b62049bac55ee117aa91/requests-2.27.0-py2.py3-none-any.whl"
        #       },
        #       {
        #         "filename": "requests-2.27.0.tar.gz",
        #         "version": "2.27.0",
        #         "requires_python": ">=2.7, !=3.0.*, !=3.1.*, !=3.2.*, !=3.3.*, !=3.4.*, !=3.5.*",
        #         "yanked": false,
        #         "url": "https://files.pythonhosted.org/packages/c0/e3/826e27b942352a74b656e8f58b4dc7ed9495ce2d4eeb498181167c615303/requests-2.27.0.tar.gz"
        #       }
        #     ]
        #   }
        # }
        sig do
          params(index_url: String)
            .returns(T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
        end
        def fetch_from_json_registry(index_url)
          json_url = index_url.sub(%r{/simple/?$}i, "/pypi/")

          Dependabot.logger.info(
            "Fetching release information from json registry at #{sanitized_url(json_url)} for #{dependency.name}"
          )

          response = registry_json_response_for_dependency(json_url)

          return nil unless response.status == 200

          begin
            data = JSON.parse(response.body)

            version_releases = data["releases"]

            releases = format_version_releases(version_releases)

            releases.sort_by(&:version).reverse
          rescue JSON::ParserError
            Dependabot.logger.warn("JSON parsing error for #{json_url}. Falling back to HTML.")
            nil
          rescue StandardError => e
            Dependabot.logger.warn("Unexpected error while fetching JSON data: #{e.message}.")
            nil
          end
        end

        # This URL points to the Simple Index API for the "requests" package on PyPI.
        # It provides an HTML listing of available package versions following PEP 503 (Simple Repository API).
        # The information found here is useful for dependency resolution and package version retrieval.
        #
        # ✅ Information available in the Simple Index:
        # - A list of package versions as anchor (`<a>`) elements.
        # - URLs to distribution files (e.g., `.tar.gz`, `.whl`).
        # - The `data-requires-python` attribute (if present) specifying the required Python version.
        # - An optional `data-yanked` attribute indicating a yanked (withdrawn) version.
        #
        # ❌ Information NOT available in the Simple Index:
        # - Release timestamps (upload time).
        # - File digests (hashes like SHA256, MD5).
        # - Package metadata such as description, author, or dependencies.
        # - Download statistics.
        # - Package type (`sdist` or `bdist_wheel`).
        #
        # To obtain full package metadata, use the PyPI JSON API:
        # - JSON API: https://pypi.org/pypi/requests/json
        #
        # More details: https://www.python.org/dev/peps/pep-0503/
        sig { params(index_url: String).returns(T::Array[Dependabot::Python::Package::PackageRelease]) }
        def fetch_from_html_registry(index_url)
          Dependabot.logger.info(
            "Fetching release information from html registry at #{sanitized_url(index_url)} for #{dependency.name}"
          )
          index_response = registry_response_for_dependency(index_url)
          if index_response.status == 401 || index_response.status == 403
            registry_index_response = registry_index_response(index_url)

            if registry_index_response.status == 401 || registry_index_response.status == 403
              raise PrivateSourceAuthenticationFailure, sanitized_url(index_url)
            end
          end

          version_releases = extract_release_details_json_from_html(index_response.body)
          releases = format_version_releases(version_releases)

          releases.sort_by(&:version).reverse
        end

        sig do
          params(html_body: String)
            .returns(T::Hash[String, T::Array[T::Hash[String, T.untyped]]]) # Returns JSON-like format
        end
        def extract_release_details_json_from_html(html_body)
          doc = Nokogiri::HTML(html_body)

          releases = {}

          doc.css("a").each do |a_tag|
            details = version_details_from_link(a_tag.to_s)
            if details && details["version"]
              releases[details["version"]] ||= []
              releases[details["version"]] << details
            end
          end

          releases
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig do
          params(link: T.nilable(String))
            .returns(T.nilable(T::Hash[String, T.untyped]))
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
            "version" => version,
            "requires_python" => requires_python_from_link(link),
            "yanked" => link.include?("data-yanked"),
            "url" => link
          }
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig do
          params(
            releases_json: T::Hash[String, T::Array[T::Hash[String, T.untyped]]]
          )
            .returns(T::Array[Dependabot::Python::Package::PackageRelease])
        end
        def format_version_releases(releases_json)
          releases_json.each_with_object([]) do |(version, release_data_array), versions|
            release_data = release_data_array.last

            next unless release_data

            release = format_version_release(version, release_data)

            next unless release

            versions << release
          end
        end

        sig do
          params(
            version: String,
            release_data: T::Hash[String, T.untyped]
          )
            .returns(T.nilable(Dependabot::Python::Package::PackageRelease))
        end
        def format_version_release(version, release_data)
          upload_time = release_data["upload_time"]
          released_at = Time.parse(upload_time) if upload_time
          yanked = release_data["yanked"] || false
          yanked_reason = release_data["yanked_reason"]
          downloads = release_data["downloads"] || -1
          url = release_data["url"]
          package_type = release_data["packagetype"]
          language = package_language(
            python_version: release_data["python_version"],
            requires_python: release_data["requires_python"]
          )

          release = Dependabot::Python::Package::PackageRelease.new(
            version: Dependabot::Python::Version.new(version),
            released_at: released_at,
            yanked: yanked,
            yanked_reason: yanked_reason,
            downloads: downloads,
            url: url,
            package_type: package_type,
            language: language
          )
          release
        end

        sig do
          params(
            python_version: T.nilable(String),
            requires_python: T.nilable(String)
          )
            .returns(T.nilable(Dependabot::Python::Package::PackageLanguage))
        end
        def package_language(python_version:, requires_python:)
          # Extract language name and version
          language_name, language_version = convert_language_version(python_version)

          # Extract language requirement
          language_requirement = build_python_requirement(requires_python)

          return nil unless language_version || language_requirement

          # Return a Language object with all details
          Dependabot::Python::Package::PackageLanguage.new(
            name: language_name,
            version: language_version,
            requirement: language_requirement
          )
        end

        sig { params(version: T.nilable(String)).returns([String, T.nilable(Dependabot::Version)]) }
        def convert_language_version(version)
          return ["python", nil] if version.nil? || version == "source"

          # Extract numeric parts dynamically (e.g., "cp37" -> "3.7", "py38" -> "3.8")
          extracted_version = version.scan(/\d+/).join(".")

          # Detect the language implementation
          language_name = if version.start_with?("cp")
                            "cpython" # CPython implementation
                          elsif version.start_with?("py")
                            "python" # General Python compatibility
                          else
                            "unknown" # Fallback for unknown cases
                          end

          # Ensure extracted version is valid before converting
          language_version =
            extracted_version.match?(/^\d+(\.\d+)*$/) ? Dependabot::Version.new(extracted_version) : nil

          Dependabot.logger.warn("Skipping invalid language_version: #{version.inspect}") if language_version.nil?

          [language_name, language_version]
        end

        sig { returns(T::Array[String]) }
        def registry_urls
          @registry_urls ||=
            Package::PackageRegistryFinder.new(
              dependency_files: dependency_files,
              credentials: credentials,
              dependency: dependency
            ).registry_urls
        end

        sig { returns(String) }
        def normalised_name
          NameNormaliser.normalise(dependency.name)
        end

        sig { params(json_url: String).returns(Excon::Response) }
        def registry_json_response_for_dependency(json_url)
          Dependabot::RegistryClient.get(
            url: "#{json_url.chomp('/')}/#{@dependency.name}/json",
            headers: { "Accept" => APPLICATION_JSON }
          )
        end

        sig { params(index_url: String).returns(Excon::Response) }
        def registry_response_for_dependency(index_url)
          Dependabot::RegistryClient.get(
            url: index_url + normalised_name + "/",
            headers: { "Accept" => APPLICATION_TEXT }
          )
        end

        sig { params(index_url: String).returns(Excon::Response) }
        def registry_index_response(index_url)
          Dependabot::RegistryClient.get(
            url: index_url,
            headers: { "Accept" => APPLICATION_TEXT }
          )
        end

        sig { params(filename: String).returns(T.nilable(String)) }
        def get_version_from_filename(filename)
          filename
            .gsub(/#{name_regex}-/i, "")
            .split(/-|\.tar\.|\.zip|\.whl/)
            .first
        end

        sig do
          params(req_string: T.nilable(String))
            .returns(T.nilable(Dependabot::Requirement))
        end
        def build_python_requirement(req_string)
          return nil unless req_string

          requirement_class.new(CGI.unescapeHTML(req_string))
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig { params(link: String).returns(T.nilable(String)) }
        def requires_python_from_link(link)
          raw_value = Nokogiri::XML(link)
                              .at_css("a")
                              &.attribute("data-requires-python")
                              &.content

          return nil unless raw_value

          CGI.unescapeHTML(raw_value) # Decodes HTML entities like &gt;=3 → >=3
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end

        sig { params(index_url: String).returns(T::Hash[String, String]) }
        def auth_headers_for(index_url)
          credential = @credentials.find { |cred| cred["index-url"] == index_url }
          return {} unless credential

          { "Authorization" => "Basic #{Base64.strict_encode64(
            "#{credential[CREDENTIALS_USERNAME]}:#{credential[CREDENTIALS_PASSWORD]}"
          )}" }
        end

        sig { returns(Regexp) }
        def name_regex
          parts = normalised_name.split(/[\s_.-]/).map { |n| Regexp.quote(n) }
          /#{parts.join("[\s_.-]")}/i
        end

        sig { params(index_url: T.nilable(String)).returns(T::Boolean) }
        def validate_index(index_url)
          return false unless index_url

          return true if index_url.match?(URI::DEFAULT_PARSER.regexp[:ABS_URI])

          raise Dependabot::DependencyFileNotResolvable,
                "Invalid URL: #{sanitized_url(index_url)}"
        end

        sig { params(index_url: String).returns(String) }
        def sanitized_url(index_url)
          index_url.sub(%r{//([^/@]+)@}, "//redacted@")
        end
      end
    end
  end
end
