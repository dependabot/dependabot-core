# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "sorbet-runtime"
require "dependabot/helm"
require "dependabot/helm/helpers"

module Dependabot
  module Helm
    module Package
      class PackageDetailsFetcher
        extend T::Sig
        # https://api.github.com/repos/prometheus-community/helm-charts/releases
        RELEASES_URL_GIT = "https://api.github.com/repos/"
        HELM_CHART_RELEASE = "/helm-charts/releases"
        HELM_CHART_INDEX_URL = "https://repo.broadcom.com/bitnami-files/index.yaml"

        sig do
          params(
            dependency: Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, credentials:)
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { params(repo_name: String).returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_from_chart(repo_name)
          return [] if repo_name.empty?

          url = RELEASES_URL_GIT + repo_name + HELM_CHART_RELEASE
          Dependabot.logger.info("Fetching graph release details from URL: #{url}")

          begin
            response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
          rescue Excon::Error => e
            Dependabot.logger.error("Failed to fetch releases from #{url}: #{e.message} ")
            []
          end

          Dependabot.logger.error("Failed call details: #{response&.body}") unless response&.status == 200
          return [] if response.nil? || response.status != 200

          parse_github_response(response)
        end

        sig { params(response: Excon::Response).returns(T::Array[GitTagWithDetail]) }
        def parse_github_response(response)
          releases = JSON.parse(response.body)
          result_lines = releases.map do |release|
            GitTagWithDetail.new(
              tag: release["tag_name"],
              release_date: release["published_at"]
            )
          end
          result_lines.sort_by(&:tag).reverse
          result_lines
          rescue JSON::ParserError => e
            Dependabot.logger.error("Failed to parse JSON response: #{e.message} response body #{response.body}")
            []
        end

        sig { params(index_url: T.nilable(String), chart_name: String).returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_helm_chart_index(index_url, chart_name)
          Dependabot.logger.info("Fetching fetch_tag_and_release_date_helm_chart_index:: #{index_url}")
          index_url = HELM_CHART_INDEX_URL if index_url.nil? || index_url.empty?
          result_lines = T.let([], T::Array[GitTagWithDetail])
          begin
            response = Excon.get(
              index_url,
              idempotent: true,
              middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
            )
          rescue Excon::Error => e
            Dependabot.logger.error("Error fetching Helm index from #{index_url}: #{e.message}")
            result_lines
          end
          Dependabot.logger.info("Received response from #{index_url} with status #{response&.status}")
          begin
            parsed_result = YAML.safe_load(response&.body)
            return result_lines unless parsed_result && parsed_result["entries"] && parsed_result["entries"][chart_name]

            parsed_result["entries"][chart_name].map do |release|
              result_lines << GitTagWithDetail.new(
                tag: release["version"], # Extract the version field
                release_date: release["created"] # Extract the created field
              )
            end
            result_lines
          rescue StandardError => e
            Dependabot.logger.error("Error parsing Helm index: #{e.message}")
            result_lines
          end
        end
      end
    end
  end
end
