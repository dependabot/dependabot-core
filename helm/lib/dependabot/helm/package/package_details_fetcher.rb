# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "sorbet-runtime"
require "dependabot/helm"

module Dependabot
  module Helm
    module Package
      class PackageDetailsFetcher
        extend T::Sig
        # https://api.github.com/repos/prometheus-community/helm-charts/releases
        RELEASES_URL_GIT = "https://api.github.com/repos/"
        APPLICATION_JSON = "JSON"
        HELM_CHART_RELEASE = "/helm-charts/releases"

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

        sig { params(repo_name: String).returns(T.any(T::Array[GitTagWithDetail], NilClass)) }
        def fetch_tag_and_release_date_from_chart(repo_name)
          return [] if repo_name.empty?

          # If not successful then test using helm history chart command
          begin
            url = RELEASES_URL_GIT + repo_name + HELM_CHART_RELEASE
            Dependabot.logger.info("Fetching graph release details from URL: #{url}")

            # Fetch the releases from the provider API
            response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
            Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200

            parse_github_response(response) if response.status == 200 # rubocop(Layout/IndentationConsistency)
          rescue Excon::Error => e
            Dependabot.logger.error("Failed to fetch releases from #{url}: #{e.message}")
            Dependabot.logger.error("Returning an empty array due to failure.")
            []
          end
        end

        sig { params(response: Excon::Response).returns(T::Array[GitTagWithDetail]) }
        def parse_github_response(response)
          Dependabot.logger.info("Parsing GitHub response body")
          begin
            # Parse the JSON response
            releases = JSON.parse(response.body)
            # Extract tag_name and published_at from each release
            result_lines = releases.map do |release|
              GitTagWithDetail.new({
                tag: release["tag_name"],
                release_date: release["published_at"]
              })
            end
            Dependabot.logger.info("Extracted release details: #{result_lines}")
            # Sort the result lines by tag in descending order
            result_lines.sort_by(&:tag).reverse
            result_lines
          rescue JSON::ParserError => e
            Dependabot.logger.error("Failed to parse JSON response: #{e.message}")
            Dependabot.logger.error("Response body: #{response.body}")
            [] # Ensure an empty array is returned on failure
          end
        end

        # https://v3-1-0.helm.sh/docs/helm/helm_history/ reference
        sig { params(response: String).returns(T::Array[GitTagWithDetail]) }
        def parse_chart_history_response(response)
          Dependabot.logger.info("Parsing GitHub response body")
          begin
            # Parse the JSON response
            releases = JSON.parse(response)
            # Extract tag_name and published_at from each release
            result_lines = releases.map do |release|
              GitTagWithDetail.new({
                tag: release["app_version"],
                release_date: release["updated"]
              })
            end
            Dependabot.logger.info("Extracted release details: #{result_lines}")
            # Sort the result lines by tag in descending order
            result_lines.sort_by(&:tag).reverse
            result_lines
          rescue JSON::ParserError => e
            Dependabot.logger.error("Failed to parse JSON response: #{e.message}")
            Dependabot.logger.error("Response body: #{response}")
            [] # Ensure an empty array is returned on failure
          end
        end

        sig { params(index_url: String, chart_name: String).returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_helm_chart_index(index_url, chart_name)
          Dependabot.logger.info("Fetching fetch_tag_and_release_date_helm_chart_index:: #{index_url}")
          begin
            response = Excon.get(
              index_url,
              idempotent: true,
              middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
            )

            Dependabot.logger.info("Received response from #{index_url} with status #{response.status}")
            parsed_result = YAML.safe_load(response.body)
            return [] unless parsed_result && parsed_result["entries"] && parsed_result["entries"][chart_name]

            result_lines = T.let([], T::Array[GitTagWithDetail])
            parsed_result["entries"][chart_name].map do |release|
              result_lines << GitTagWithDetail.new(
                tag: release["version"], # Extract the version field
                release_date: release["created"] # Extract the created field
              )
            end

            result_lines
          rescue Excon::Error => e
            Dependabot.logger.error("Error fetching Helm index from #{index_url}: #{e.message}")
            nil
          rescue StandardError => e
            Dependabot.logger.error("Error parsing Helm index: #{e.message}")
            nil
          end
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        sig { params(tags: T::Array[String], repo_url: String).returns(T.any(T::Array[GitTagWithDetail], NilClass)) }
        def fetch_tags_with_release_date_using_oci(tags, repo_url)
          Dependabot.logger.info("Searching OCI tags for: #{tags.join(', ')} #{repo_url}")
          git_tag_with_release_date = T.let([], T::Array[GitTagWithDetail])
          return git_tag_with_release_date if tags.empty?

          tags.each do |tag|
            response = Dependabot::SharedHelpers.run_shell_command(
              "oras manifest fetch docker.io/library/nginx:#{tag} --output json",
              fingerprint: "docker.io/library/nginx:{tag} --output json"
            ).strip

            parsed_response = JSON.parse(response)
            git_tag_with_release_date << GitTagWithDetail.new({
              tag: tag,
              release_date: parsed_response.dig("annotations", "org.opencontainers.image.created")
            })
          rescue JSON::ParserError => e
            Dependabot.logger.error("Failed to parse JSON response for tag #{tag}: #{e.message}")
          rescue StandardError => e
            Dependabot.logger.error("Error in using command oras manifest fetch docker.io/library/nginx:#{tag}
               --output, and the error message is #{e.message}")
          end
          return git_tag_with_release_date if git_tag_with_release_date.size.positive?

          tags.each do |tag|
            response = Dependabot::SharedHelpers.run_shell_command(
              "oras manifest fetch #{repo_url}:#{tag} --output json",
              fingerprint: "oras manifest fetch <repo_url>:<tag> --output json"
            ).strip

            parsed_response = JSON.parse(response)
            git_tag_with_release_date << GitTagWithDetail.new({
              tag: tag,
              release_date: parsed_response.dig("annotations", "org.opencontainers.image.created")
            })
          rescue JSON::ParserError => e
            Dependabot.logger.error("Failed to parse JSON response for tag #{tag}: #{e.message}")
          rescue StandardError => e
            Dependabot.logger.error("Error fetching details for tag #{tag}: #{e.message}")
          end
          git_tag_with_release_date
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
