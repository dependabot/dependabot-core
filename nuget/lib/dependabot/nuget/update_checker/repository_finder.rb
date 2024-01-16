# typed: true
# frozen_string_literal: true

require "excon"
require "nokogiri"
require "dependabot/errors"
require "dependabot/update_checkers/base"
require "dependabot/registry_client"
require "dependabot/nuget/cache_manager"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
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

        attr_reader :dependency, :credentials, :config_files

        def find_dependency_urls
          @find_dependency_urls ||=
            known_repositories.flat_map do |details|
              if details.fetch(:url) == DEFAULT_REPOSITORY_URL
                # Save a request for the default URL, since we already know how
                # it addresses packages
                next default_repository_details
              end

              NugetClient.build_repository_details(details, dependency.name)
            end.compact.uniq
        end

        def base_url_from_v3_metadata(metadata)
          metadata
            .fetch("resources", [])
            .find { |r| r.fetch("@type") == "PackageBaseAddress/3.0.0" }
            &.fetch("@id")
        end

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
            credentials
            .select { |cred| cred["type"] == "nuget_feed" }
            .map { |c| { url: c.fetch("url"), token: c["token"] } }
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

          # regular package sources
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

          sources.select! { |s| s.fetch(:url)&.include?("://") }

          add_config_file_credentials(sources: sources, doc: doc)
          sources.each { |details| details.delete(:key) }

          sources
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity

        def default_repository_details
          RepositoryFinder.get_default_repository_details(dependency.name)
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

            source_details[:token] = "#{username}:#{password}"
          rescue Nokogiri::XML::XPath::SyntaxError
            # Any non-ascii characters in the tag with cause a syntax error
            next source_details[:token] = nil
          end

          sources
        end
        # rubocop:enable Metrics/PerceivedComplexity
      end
    end
  end
end
