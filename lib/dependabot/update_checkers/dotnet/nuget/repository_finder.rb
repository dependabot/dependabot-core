# frozen_string_literal: true

require "excon"
require "nokogiri"
require "dependabot/update_checkers/dotnet/nuget"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module Dotnet
      class Nuget
        class RepositoryFinder
          DEFAULT_REPOSITORY_URL = "https://api.nuget.org/v3/index.json"

          def initialize(dependency:, credentials:, config_file: nil)
            @dependency  = dependency
            @credentials = credentials
            @config_file = config_file
          end

          def dependency_urls
            find_dependency_urls
          end

          private

          attr_reader :dependency, :credentials, :config_file

          def find_dependency_urls
            @find_dependency_urls ||=
              known_repositories.flat_map do |details|
                if details.fetch("url") == DEFAULT_REPOSITORY_URL
                  # Save a request for the default URL, since we already how
                  # it addresses packages
                  next default_repository_details
                end

                repo_metadata_response = Excon.get(
                  details.fetch("url"),
                  idempotent: true,
                  **SharedHelpers.excon_defaults
                )

                next unless repo_metadata_response.status == 200
                base_url =
                  JSON.parse(repo_metadata_response.body).
                  fetch("resources", []).
                  find { |r| r.fetch("@type") == "PackageBaseAddress/3.0.0" }&.
                  fetch("@id")

                {
                  repository_url: details.fetch("url"),
                  versions_url:
                    File.join(base_url, dependency.name.downcase, "index.json")
                }
              rescue Excon::Error::Timeout, Excon::Error::Socket
                nil
              end.compact.uniq
          end

          def known_repositories
            return @known_repositories if @known_repositories
            @known_repositories = []
            @known_repositories += credential_repositories
            @known_repositories += config_file_repositories

            if @known_repositories.empty?
              @known_repositories << {
                "url" => DEFAULT_REPOSITORY_URL,
                "username" => nil,
                "password" => nil
              }
            end

            @known_repositories
          end

          def credential_repositories
            credentials.select { |cred| cred["type"] == "nuget_repository" }
          end

          def config_file_repositories
            return [] unless config_file

            doc = Nokogiri::XML(config_file.content)
            doc.remove_namespaces!
            doc.css("configuration > packageSources > add").map do |node|
              {
                "key" =>
                  node.attribute("key")&.value&.strip ||
                    node.at_xpath("./key")&.content&.strip,
                "url" =>
                  node.attribute("value")&.value&.strip ||
                    node.at_xpath("./value")&.content&.strip
              }
            end
          end

          def default_repository_details
            {
              repository_url: DEFAULT_REPOSITORY_URL,
              versions_url:   "https://api.nuget.org/v3-flatcontainer/"\
                              "#{dependency.name.downcase}/index.json"
            }
          end
        end
      end
    end
  end
end
