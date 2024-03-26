# typed: strict
# frozen_string_literal: true

require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/update_checkers/base"
require "dependabot/registry_client"
require "dependabot/nuget/cache_manager"
require "dependabot/nuget/http_response_helpers"

module Dependabot
  module Nuget
    class RepositoryFinder
      extend T::Sig

      DEFAULT_REPOSITORY_URL = "https://api.nuget.org/v3/index.json"
      DEFAULT_REPOSITORY_API_KEY = "nuget.org"

      sig do
        params(
          dependency: Dependabot::Dependency,
          credentials: T::Array[Dependabot::Credential],
          config_files: T::Array[Dependabot::DependencyFile]
        ).void
      end
      def initialize(dependency:, credentials:, config_files: [])
        @dependency  = dependency
        @credentials = credentials
        @config_files = config_files
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def dependency_urls
        find_dependency_urls
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def known_repositories
        return @known_repositories if @known_repositories

        @known_repositories ||= T.let([], T.nilable(T::Array[T::Hash[Symbol, String]]))
        @known_repositories += credential_repositories
        @known_repositories += config_file_repositories

        @known_repositories << { url: DEFAULT_REPOSITORY_URL, token: nil } if @known_repositories.empty?

        @known_repositories = @known_repositories.map do |repo|
          { url: URI::DEFAULT_PARSER.escape(repo[:url]), token: repo[:token] }
        end
        @known_repositories.uniq
      end

      sig { params(dependency_name: String).returns(T::Hash[Symbol, T.untyped]) }
      def self.get_default_repository_details(dependency_name)
        {
          base_url: "https://api.nuget.org/v3-flatcontainer/",
          registration_url: "https://api.nuget.org/v3/registration5-gz-semver2/#{dependency_name.downcase}/index.json",
          repository_url: DEFAULT_REPOSITORY_URL,
          versions_url: "https://api.nuget.org/v3-flatcontainer/" \
                        "#{dependency_name.downcase}/index.json",
          search_url: "https://azuresearch-usnc.nuget.org/query" \
                      "?q=#{dependency_name.downcase}&prerelease=true&semVerLevel=2.0.0",
          auth_header: {},
          repository_type: "v3"
        }
      end

      private

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :config_files

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def find_dependency_urls
        @find_dependency_urls ||=
          T.let(
            known_repositories.flat_map do |details|
              if details.fetch(:url) == DEFAULT_REPOSITORY_URL
                # Save a request for the default URL, since we already know how
                # it addresses packages
                next default_repository_details
              end

              build_url_for_details(details)
            end.compact.uniq,
            T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
          )
      end

      sig { params(repo_details: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_url_for_details(repo_details)
        url = repo_details.fetch(:url)
        url_obj = URI.parse(url)
        if url_obj.is_a?(URI::HTTP)
          details = build_url_for_details_remote(repo_details)
        elsif url_obj.is_a?(URI::File)
          details = {
            base_url: url,
            repository_type: "local"
          }
        end

        details
      end

      sig { params(repo_details: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def build_url_for_details_remote(repo_details)
        response = get_repo_metadata(repo_details)
        check_repo_response(response, repo_details)
        return unless response.status == 200

        body = HttpResponseHelpers.remove_wrapping_zero_width_chars(response.body)
        parsed_json = JSON.parse(body)
        base_url = base_url_from_v3_metadata(parsed_json)
        search_url = search_url_from_v3_metadata(parsed_json)
        registration_url = registration_url_from_v3_metadata(parsed_json)

        details = {
          base_url: base_url,
          repository_url: repo_details.fetch(:url),
          auth_header: auth_header_for_token(repo_details.fetch(:token)),
          repository_type: "v3"
        }
        if base_url
          details[:versions_url] =
            File.join(base_url, dependency.name.downcase, "index.json")
        end
        if search_url
          details[:search_url] =
            search_url + "?q=#{dependency.name.downcase}&prerelease=true&semVerLevel=2.0.0"
        end

        if registration_url
          details[:registration_url] = File.join(registration_url, dependency.name.downcase, "index.json")
        end

        details
      rescue JSON::ParserError
        build_v2_url(T.must(response), repo_details)
      rescue Excon::Error::Timeout, Excon::Error::Socket
        handle_timeout(repo_metadata_url: repo_details.fetch(:url))
      end

      sig { params(repo_details: T::Hash[Symbol, T.untyped]).returns(Excon::Response) }
      def get_repo_metadata(repo_details)
        url = repo_details.fetch(:url)
        cache = CacheManager.cache("repo_finder_metadatacache")
        if cache[url]
          cache[url]
        else
          result = Dependabot::RegistryClient.get(
            url: url,
            headers: auth_header_for_token(repo_details.fetch(:token))
          )
          cache[url] = result
          result
        end
      end

      sig { params(metadata: T::Hash[String, T::Array[T::Hash[String, T.untyped]]]).returns(T.nilable(String)) }
      def base_url_from_v3_metadata(metadata)
        metadata
          .fetch("resources", [])
          .find { |r| r.fetch("@type") == "PackageBaseAddress/3.0.0" }
          &.fetch("@id")
      end

      sig { params(metadata: T::Hash[String, T::Array[T::Hash[String, T.untyped]]]).returns(T.nilable(String)) }
      def registration_url_from_v3_metadata(metadata)
        allowed_registration_types = %w(
          RegistrationsBaseUrl
          RegistrationsBaseUrl/3.0.0-beta
          RegistrationsBaseUrl/3.0.0-rc
          RegistrationsBaseUrl/3.4.0
          RegistrationsBaseUrl/3.6.0
        )
        metadata
          .fetch("resources", [])
          .find { |r| allowed_registration_types.find { |s| r.fetch("@type") == s } }
          &.fetch("@id")
      end

      sig { params(metadata: T::Hash[String, T::Array[T::Hash[String, T.untyped]]]).returns(T.nilable(String)) }
      def search_url_from_v3_metadata(metadata)
        # allowable values from here: https://learn.microsoft.com/en-us/nuget/api/search-query-service-resource#versioning
        allowed_search_types = %w(
          SearchQueryService
          SearchQueryService/3.0.0-beta
          SearchQueryService/3.0.0-rc
          SearchQueryService/3.5.0
        )
        metadata
          .fetch("resources", [])
          .find { |r| allowed_search_types.find { |s| r.fetch("@type") == s } }
          &.fetch("@id")
      end

      sig do
        params(
          response: Excon::Response,
          repo_details: T::Hash[Symbol, T.untyped]
        )
          .returns(T::Hash[Symbol, T.untyped])
      end
      def build_v2_url(response, repo_details)
        doc = Nokogiri::XML(response.body)

        doc.remove_namespaces!
        base_url = doc.at_xpath("service")&.attributes
                      &.fetch("base", nil)&.value

        base_url ||= repo_details.fetch(:url)

        {
          base_url: base_url,
          repository_url: base_url,
          versions_url: File.join(
            base_url.delete_suffix("/"),
            "FindPackagesById()?id='#{dependency.name}'"
          ),
          auth_header: auth_header_for_token(repo_details.fetch(:token)),
          repository_type: "v2"
        }
      end

      sig { params(response: Excon::Response, details: T::Hash[Symbol, T.untyped]).void }
      def check_repo_response(response, details)
        return unless [401, 402, 403].include?(response.status)
        raise if details.fetch(:url) == DEFAULT_REPOSITORY_URL

        raise PrivateSourceAuthenticationFailure, details.fetch(:url)
      end

      sig { params(repo_metadata_url: String).returns(T.noreturn) }
      def handle_timeout(repo_metadata_url:)
        raise if repo_metadata_url == DEFAULT_REPOSITORY_URL

        raise PrivateSourceTimedOut, repo_metadata_url
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def credential_repositories
        @credential_repositories ||=
          T.let(
            credentials
            .select { |cred| cred["type"] == "nuget_feed" && cred["url"] }
            .map { |c| { url: c.fetch("url"), token: c["token"] } },
            T.nilable(T::Array[T::Hash[Symbol, String]])
          )
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def config_file_repositories
        config_files.flat_map { |file| repos_from_config_file(file) }
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      sig { params(config_file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, String]]) }
      def repos_from_config_file(config_file)
        doc = Nokogiri::XML(config_file.content)
        doc.remove_namespaces!
        # analogous to having a root config with the default repository
        base_sources = [{ url: DEFAULT_REPOSITORY_URL, key: "nuget.org" }]

        sources = T.let([], T::Array[T::Hash[Symbol, String]])

        # regular package sources
        doc.css("configuration > packageSources").children.each do |node|
          if node.name == "clear"
            sources.clear
            base_sources.clear
          else
            key = node.attribute("key")&.value&.strip || node.at_xpath("./key")&.content&.strip
            url = node.attribute("value")&.value&.strip || node.at_xpath("./value")&.content&.strip
            url = expand_windows_style_environment_variables(url) if url

            # if the path isn't absolute it's relative to the nuget.config file
            if url
              unless url.include?("://") || Pathname.new(url).absolute?
                url = Pathname(config_file.directory).join(url).to_path
              end
              sources << { url: url, key: key }
            end
          end
        end

        # signed package sources
        # https://learn.microsoft.com/en-us/nuget/reference/nuget-config-file#trustedsigners-section
        doc.xpath("/configuration/trustedSigners/repository").each do |node|
          name = node.attribute("name")&.value&.strip
          service_index = node.attribute("serviceIndex")&.value&.strip
          sources << { url: service_index, key: name }
        end

        sources += base_sources # TODO: quirky overwrite behavior
        disabled_sources = disabled_sources(doc)
        sources.reject! do |s|
          disabled_sources.include?(s[:key])
        end

        sources.reject! do |s|
          known_urls = credential_repositories.map { |cr| cr.fetch(:url) }
          known_urls.include?(s.fetch(:url))
        end

        add_config_file_credentials(sources: sources, doc: doc)
        sources.each { |details| details.delete(:key) }

        sources
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def default_repository_details
        RepositoryFinder.get_default_repository_details(dependency.name)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(doc: Nokogiri::XML::Document).returns(T::Array[String]) }
      def disabled_sources(doc)
        doc.css("configuration > disabledPackageSources > add").filter_map do |node|
          value = node.attribute("value")&.value ||
                  node.at_xpath("./value")&.content

          if value&.strip&.downcase == "true"
            node.attribute("key")&.value&.strip ||
              node.at_xpath("./key")&.content&.strip
          end
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # rubocop:disable Metrics/PerceivedComplexity
      sig do
        params(
          sources: T::Array[T::Hash[Symbol, T.nilable(String)]],
          doc: Nokogiri::XML::Document
        )
          .void
      end
      def add_config_file_credentials(sources:, doc:)
        sources.each do |source_details|
          key = source_details.fetch(:key)
          next source_details[:token] = nil unless key
          next source_details[:token] = nil if key.match?(/^\d/)

          tag = key.gsub(" ", "_x0020_")
          creds_nodes = doc.css("configuration > packageSourceCredentials " \
                                "> #{tag} > add")

          username =
            creds_nodes
            .find { |n| n.attribute("key")&.value == "Username" }
            &.attribute("value")&.value
          password =
            creds_nodes
            .find { |n| n.attribute("key")&.value == "ClearTextPassword" }
            &.attribute("value")&.value

          # NOTE: We have to look for plain text passwords, as we have no
          # way of decrypting encrypted passwords. For the same reason we
          # don't fetch API keys from the nuget.config at all.
          next source_details[:token] = nil unless username && password

          expanded_username = expand_windows_style_environment_variables(username)
          expanded_password = expand_windows_style_environment_variables(password)
          source_details[:token] = "#{expanded_username}:#{expanded_password}"
        rescue Nokogiri::XML::XPath::SyntaxError
          # Any non-ascii characters in the tag with cause a syntax error
          next source_details[:token] = nil
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(string: String).returns(String) }
      def expand_windows_style_environment_variables(string)
        # NuGet.Config files can have Windows-style environment variables that need to be replaced
        # https://learn.microsoft.com/en-us/nuget/reference/nuget-config-file#using-environment-variables
        string.gsub(/%([^%]+)%/) do
          environment_variable_name = T.must(::Regexp.last_match(1))
          environment_variable_value = ENV.fetch(environment_variable_name, nil)
          if environment_variable_value
            environment_variable_value
          else
            # report that the variable couldn't be expanded, then replace it as-is
            Dependabot.logger.warn <<~WARN
              The variable '%#{environment_variable_name}%' could not be expanded in NuGet.Config
            WARN
            "%#{environment_variable_name}%"
          end
        end
      end

      sig { params(token: T.nilable(String)).returns(T::Hash[String, String]) }
      def auth_header_for_token(token)
        return {} unless token

        if token.include?(":")
          encoded_token = Base64.encode64(token).delete("\n")
          { "Authorization" => "Basic #{encoded_token}" }
        elsif Base64.decode64(token).ascii_only? &&
              Base64.decode64(token).include?(":")
          { "Authorization" => "Basic #{token.delete("\n")}" }
        else
          { "Authorization" => "Bearer #{token}" }
        end
      end
    end
  end
end
