# frozen_string_literal: true

require "excon"
require "nokogiri"
require "dependabot/errors"
require "dependabot/nuget/update_checker"
require "dependabot/registry_client"

module Dependabot
  module Nuget
    class UpdateChecker
      class RepositoryFinder
        DEFAULT_REPOSITORY_URL = "https://api.nuget.org/v3/index.json"
        DEFAULT_REPOSITORY_API_KEY = "nuget.org"

        def initialize(dependency:, credentials:, config_files: [])
          @dependency  = dependency
          @credentials = credentials
          @config_files = config_files
        end

        def dependency_urls
          find_dependency_urls
        end

        private

        attr_reader :dependency, :credentials, :config_files

        def find_dependency_urls
          @find_dependency_urls ||=
            known_repositories.flat_map do |details|
              if details.fetch(:url) == DEFAULT_REPOSITORY_URL
                # Save a request for the default URL, since we already know how
                # it addresses packages
                next default_repository_details
              end

              build_url_for_details(details)
            end.compact.uniq
        end

        def build_url_for_details(repo_details)
          response = get_repo_metadata(repo_details)
          check_repo_response(response, repo_details)
          return unless response.status == 200

          body = remove_wrapping_zero_width_chars(response.body)
          base_url = base_url_from_v3_metadata(JSON.parse(body))
          search_url = search_url_from_v3_metadata(JSON.parse(body))

          details = {
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
          details
        rescue JSON::ParserError
          build_v2_url(response, repo_details)
        rescue Excon::Error::Timeout, Excon::Error::Socket
          handle_timeout(repo_metadata_url: repo_details.fetch(:url))
        end

        def get_repo_metadata(repo_details)
          Dependabot::RegistryClient.get(
            url: repo_details.fetch(:url),
            headers: auth_header_for_token(repo_details.fetch(:token))
          )
        end

        def base_url_from_v3_metadata(metadata)
          metadata.
            fetch("resources", []).
            find { |r| r.fetch("@type") == "PackageBaseAddress/3.0.0" }&.
            fetch("@id")
        end

        def search_url_from_v3_metadata(metadata)
          metadata.
            fetch("resources", []).
            find { |r| r.fetch("@type") == "SearchQueryService" }&.
            fetch("@id")
        end

        def build_v2_url(response, repo_details)
          doc = Nokogiri::XML(response.body)

          doc.remove_namespaces!
          base_url = doc.at_xpath("service")&.attributes&.
                     fetch("base", nil)&.value

          base_url ||= repo_details.fetch(:url)

          {
            repository_url: base_url,
            versions_url: File.join(
              base_url,
              "FindPackagesById()?id='#{dependency.name}'"
            ),
            auth_header: auth_header_for_token(repo_details.fetch(:token)),
            repository_type: "v2"
          }
        end

        def check_repo_response(response, details)
          return unless [401, 402, 403].include?(response.status)
          raise if details.fetch(:url) == DEFAULT_REPOSITORY_URL

          raise PrivateSourceAuthenticationFailure, details.fetch(:url)
        end

        def handle_timeout(repo_metadata_url:)
          raise if repo_metadata_url == DEFAULT_REPOSITORY_URL

          raise PrivateSourceTimedOut, repo_metadata_url
        end

        def known_repositories
          return @known_repositories if @known_repositories

          @known_repositories = []
          @known_repositories += credential_repositories
          @known_repositories += config_file_repositories

          @known_repositories << { url: DEFAULT_REPOSITORY_URL, token: nil } if @known_repositories.empty?

          @known_repositories.uniq
        end

        def credential_repositories
          @credential_repositories ||=
            credentials.
            select { |cred| cred["type"] == "nuget_feed" }.
            map { |c| { url: c.fetch("url"), token: c["token"] } }
        end

        def config_file_repositories
          config_files.flat_map { |file| repos_from_config_file(file) }
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        def repos_from_config_file(config_file)
          doc = Nokogiri::XML(config_file.content)
          doc.remove_namespaces!
          # analogous to having a root config with the default repository
          base_sources = [{ url: DEFAULT_REPOSITORY_URL, key: "nuget.org" }]

          sources = []
          doc.css("configuration > packageSources").children.each do |node|
            if node.name == "clear"
              sources.clear
              base_sources.clear
            else
              key = node.attribute("key")&.value&.strip || node.at_xpath("./key")&.content&.strip
              url = node.attribute("value")&.value&.strip || node.at_xpath("./value")&.content&.strip
              sources << { url: url, key: key }
            end
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

          sources.select! { |s| s.fetch(:url)&.include?("://") }

          add_config_file_credentials(sources: sources, doc: doc)
          sources.each { |details| details.delete(:key) }

          sources
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity

        def default_repository_details
          {
            repository_url: DEFAULT_REPOSITORY_URL,
            versions_url: "https://api.nuget.org/v3-flatcontainer/" \
                          "#{dependency.name.downcase}/index.json",
            search_url: "https://azuresearch-usnc.nuget.org/query" \
                        "?q=#{dependency.name.downcase}&prerelease=true&semVerLevel=2.0.0",
            auth_header: {},
            repository_type: "v3"
          }
        end

        # rubocop:disable Metrics/PerceivedComplexity
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
        def add_config_file_credentials(sources:, doc:)
          sources.each do |source_details|
            key = source_details.fetch(:key)
            next source_details[:token] = nil unless key
            next source_details[:token] = nil if key.match?(/^\d/)

            tag = key.gsub(" ", "_x0020_")
            creds_nodes = doc.css("configuration > packageSourceCredentials " \
                                  "> #{tag} > add")

            username =
              creds_nodes.
              find { |n| n.attribute("key")&.value == "Username" }&.
              attribute("value")&.value
            password =
              creds_nodes.
              find { |n| n.attribute("key")&.value == "ClearTextPassword" }&.
              attribute("value")&.value

            # NOTE: We have to look for plain text passwords, as we have no
            # way of decrypting encrypted passwords. For the same reason we
            # don't fetch API keys from the nuget.config at all.
            next source_details[:token] = nil unless username && password

            source_details[:token] = "#{username}:#{password}"
          rescue Nokogiri::XML::XPath::SyntaxError
            # Any non-ascii characters in the tag with cause a syntax error
            next source_details[:token] = nil
          end

          sources
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def remove_wrapping_zero_width_chars(string)
          string.force_encoding("UTF-8").encode.
            gsub(/\A[\u200B-\u200D\uFEFF]/, "").
            gsub(/[\u200B-\u200D\uFEFF]\Z/, "")
        end

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
end
