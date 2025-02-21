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

          @available_versions = T.let(nil, T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
          @index_urls = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Python::Package::PackageRelease]) }
        def fetch
          index_urls.flat_map do |index_url|
            validate_index(index_url)

            package_details = fetch_from_registry(index_url)

            package_details || []
          rescue Excon::Error::Timeout, Excon::Error::Socket
            raise if MAIN_PYPI_INDEXES.include?(index_url)

            raise PrivateSourceTimedOut, sanitized_url(index_url)
          rescue URI::InvalidURIError
            raise DependencyFileNotResolvable, "Invalid URL: #{sanitized_url(index_url)}"
          end
        end

        sig do
          params(index_url: String)
            .returns(T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
        end
        def fetch_from_registry(index_url)
          if Dependabot::Experiments.enabled?(:enable_cooldown_for_python)
            Dependabot.logger.info(
              "Fetching metadata from registry at #{sanitized_url(index_url)} for #{dependency.name}"
            )
            metadata = fetch_from_json_registry(index_url)

            return metadata if metadata&.any?

            Dependabot.logger.warn("No valid versions found via JSON API. Falling back to HTML.")
          end
          fetch_from_html_registry(index_url)
        rescue StandardError => e
          Dependabot.logger.warn("Unexpected error in JSON fetch: #{e.message}. Falling back to HTML.")
          fetch_from_html_registry(index_url)
        end

        sig do
          params(index_url: String)
            .returns(T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
        end
        def fetch_from_json_registry(index_url)
          Dependabot.logger.info(
            "Fetching metadata from json registry at #{sanitized_url(index_url)} for #{dependency.name}"
          )
          json_url = index_url.sub(%r{/simple/?$}i, "/pypi/")

          auth_headers = auth_headers_for(index_url)

          response = Dependabot::RegistryClient.get(
            url: "#{json_url.chomp('/')}/#{@dependency.name}/json",
            headers: {
              "Accept" => APPLICATION_JSON,
              **auth_headers
            }
          )

          return nil unless response.status == 200

          begin
            data = JSON.parse(response.body)
            releases = extract_release_details_from_json(data["releases"] || {})

            releases.sort_by(&:version).reverse
          rescue JSON::ParserError
            Dependabot.logger.warn("JSON parsing error for #{json_url}. Falling back to HTML.")
            nil
          rescue StandardError => e
            Dependabot.logger.warn("Unexpected error while fetching JSON data: #{e.message}.")
            nil
          end
        end

        # See https://www.python.org/dev/peps/pep-0503/ for details of the
        # Simple Repository API we use here.
        sig { params(index_url: String).returns(T::Array[Dependabot::Python::Package::PackageRelease]) }
        def fetch_from_html_registry(index_url)
          index_response = registry_response_for_dependency(index_url)
          if index_response.status == 401 || index_response.status == 403
            registry_index_response = registry_index_response(index_url)

            if registry_index_response.status == 401 || registry_index_response.status == 403
              raise PrivateSourceAuthenticationFailure, sanitized_url(index_url)
            end
          end

          version_links = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
          index_response.body.scan(%r{<a\s[^>]*?>.*?<\/a>}m) do
            details = version_details_from_link(Regexp.last_match.to_s)
            version_links << details if details
          end

          version_links.compact.map do |details|
            python_requirement = details.fetch(:python_requirement, nil)

            if python_requirement
              language = Dependabot::Python::Package::PackageLanguage.new(
                name: PYTHON,
                requirement: python_requirement
              )
            end

            Dependabot::Python::Package::PackageRelease.new(
              version: version_class.new(details.fetch(:version)),
              released_at: nil, # HTML doesn't provide release timestamps
              yanked: details.fetch(:yanked),
              yanked_reason: nil, # No way to extract this from HTML
              downloads: nil,       # No download count available in HTML
              url: details.fetch(:url),
              package_type: nil,    # No package type info from HTML
              language: language
            )
          end
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

        sig { params(index_url: String).returns(String) }
        def sanitized_url(index_url)
          index_url.sub(%r{//([^/@]+)@}, "//redacted@")
        end

        sig { params(index_url: String).returns(Excon::Response) }
        def registry_response_for_dependency(index_url)
          Dependabot::RegistryClient.get(
            url: index_url + normalised_name + "/",
            headers: { "Accept" => "text/html" }
          )
        end

        sig { returns(String) }
        def normalised_name
          NameNormaliser.normalise(dependency.name)
        end

        sig { params(index_url: String).returns(Excon::Response) }
        def registry_index_response(index_url)
          Dependabot::RegistryClient.get(
            url: index_url,
            headers: { "Accept" => "text/html" }
          )
        end

        sig do
          params(
            releases_json: T::Hash[String, T::Array[T::Hash[String, T.untyped]]]
          )
            .returns(T::Array[Dependabot::Python::Package::PackageRelease])
        end
        def extract_release_details_from_json(releases_json)
          releases_json.each_with_object([]) do |(version, release_data_array), versions|
            release_data = release_data_array.first

            next unless release_data

            release = extract_release_from_release_json_data(version, release_data)

            next unless release

            versions << release
          end
        end

        # Example of a JSON response:
        # {
        #   "comment_text": "",
        #   "digests": {
        #     "blake2b_256": "62ca338cf287e172099e4500cfa2cb580d2c9a1874427a8a14324d7a4c9d01b1",
        #     "md5": "fac5635391778e2394a411d37e69ae5e",
        #     "sha256": "37684324da8aca40e88fa2f7faa526cc116d74e979c2ac5d9119fe6e1bb5ced5"
        #   },
        #   "downloads": -1,
        #   "filename": "requests-0.13.2.tar.gz",
        #   "has_sig": false,
        #   "md5_digest": "fac5635391778e2394a411d37e69ae5e",
        #   "packagetype": "sdist",
        #   "python_version": "source",
        #   "requires_python": null,
        #   "size": 514484,
        #   "upload_time": "2012-06-29T02:37:41",
        #   "upload_time_iso_8601": "2012-06-29T02:37:41.500479Z",
        #   "url": "https://files.pythonhosted.org/packages/62/ca/338cf287e172099e4500cfa2cb580d2c9a1874427a8a14324d7a4c9d01b1/requests-0.13.2.tar.gz",
        #   "yanked": false,
        #   "yanked_reason": null
        # }
        sig do
          params(
            version: String,
            release_data: T::Hash[String, T.untyped]
          )
            .returns(T.nilable(Dependabot::Python::Package::PackageRelease))
        end
        def extract_release_from_release_json_data(version, release_data)
          upload_time = release_data["upload_time"]
          released_at = Time.parse(upload_time) if upload_time
          yanked = release_data["yanked"] || false
          yanked_reason = release_data["yanked_reason"]
          downloads = release_data["downloads"] || -1
          url = release_data["url"]
          package_type = release_data["packagetype"]
          language = package_language(release_data)

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
          params(release_data: T::Hash[String, T.untyped])
            .returns(T.nilable(Dependabot::Python::Package::PackageLanguage))
        end
        def package_language(release_data)
          # Extract language name and version
          language_name, language_version = convert_language_version(release_data["python_version"])

          # Extract language requirement
          language_requirement = build_python_requirement(release_data["requires_python"])

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
            yanked: link.include?("data-yanked"),
            url: link
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

          sanitized_url = index_url.sub(%r{//([^/@]+)@}, "//redacted@")

          return if index_url.match?(URI::DEFAULT_PARSER.regexp[:ABS_URI])

          raise Dependabot::DependencyFileNotResolvable,
                "Invalid URL: #{sanitized_url}"
        end
      end
    end
  end
end
