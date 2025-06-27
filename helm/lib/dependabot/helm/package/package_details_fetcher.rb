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

        sig { params(repo_name: String).returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_from_chart(repo_name) # rubocop:disable Metrics/AbcSize,Metrics/PerceivedComplexity
          return [] unless repo_name.empty?

          url = RELEASES_URL_GIT + repo_name + HELM_CHART_RELEASE
          Dependabot.logger.info("Fetching graph release details from URL: #{url}")
          result_lines = T.let([], T::Array[GitTagWithDetail])
          # Fetch the releases from the provider API
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
          Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
          return result_lines unless response.status == 200

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
        end
        # RuboCop:enable Metrics/AbcSize, Metrics/MethodLength
      end
    end
  end
end
