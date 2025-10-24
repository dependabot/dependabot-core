# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "sorbet-runtime"
require "dependabot/swift"

module Dependabot
  module Opentofu
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        RELEASES_URL_GIT = "https://api.github.com/repos/"
        RELEASE_URL_FOR_PROVIDER = "https://api.opentofu.org/registry/docs/providers/"
        RELEASE_URL_FOR_MODULE = "https://api.opentofu.org/registry/docs/modules/"
        APPLICATION_JSON = "JSON"
        # https://api.opentofu.org/registry/docs/providers/hashicorp/aws/index.json
        # https://api.opentofu.org/registry/docs/modules/hashicorp/consul/aws/index.json

        ELIGIBLE_SOURCE_TYPES = T.let(
          %w(git provider registry).freeze,
          T::Array[String]
        )

        sig do
          params(
            dependency: Dependency,
            credentials: T::Array[Dependabot::Credential],
            git_commit_checker: Dependabot::GitCommitChecker
          ).void
        end
        def initialize(dependency:, credentials:, git_commit_checker:)
          @dependency = dependency
          @credentials = credentials
          @git_commit_checker = git_commit_checker
        end

        sig { returns(Dependabot::GitCommitChecker) }
        attr_reader :git_commit_checker

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date
          truncate_github_url = @dependency.name.gsub("github.com/", "")
          url = RELEASES_URL_GIT + "#{truncate_github_url}/releases"
          result_lines = T.let([], T::Array[GitTagWithDetail])
          # Fetch the releases from the GitHub API
          response = Excon.get(
            url,
            headers: { "User-Agent" => "Dependabot (dependabot.com)",
                       "Accept" => "application/vnd.github.v3+json" }
          )
          Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
          return result_lines unless response.status == 200

          # Parse the JSON response
          releases = JSON.parse(response.body)

          # Extract version names and release dates into a hash
          releases.map do |release|
            result_lines << GitTagWithDetail.new(
              tag: release["tag_name"],
              release_date: release["published_at"]
            )
          end

          # sort the result lines by tag in descending order
          result_lines = result_lines.sort_by(&:tag).reverse
          # Log the extracted details for debugging
          Dependabot.logger.info("Extracted release details: #{result_lines}")
          result_lines
        end

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_from_provider
          return [] unless dependency_source_details

          url = RELEASE_URL_FOR_PROVIDER + dependency_source_details&.fetch(:module_identifier) + "/index.json"
          Dependabot.logger.info("Fetching provider release details from URL: #{url}")
          result_lines = T.let([], T::Array[GitTagWithDetail])
          # Fetch the releases from the provider API
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
          Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
          return result_lines unless response.status == 200

          # Parse the JSON response
          releases = JSON.parse(response.body).fetch("versions", [])
          # Check if releases is an array and not empty
          return result_lines unless releases.is_a?(Array) && !releases.empty?

          # Extract version names and release dates into result_lines
          releases.each do |release|
            result_lines << GitTagWithDetail.new(
              tag: release["id"],
              release_date: release["published"]
            )
          end
          # Sort the result lines by tag in descending order
          result_lines.sort_by(&:tag).reverse
        end
        # RuboCop:enable Metrics/AbcSize, Metrics/MethodLength

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_from_module
          return [] unless dependency_source_details

          url = RELEASE_URL_FOR_MODULE + dependency_source_details&.fetch(:module_identifier) + "/index.json"
          Dependabot.logger.info("Fetching provider release details from URL: #{url}")
          result_lines = T.let([], T::Array[GitTagWithDetail])
          # Fetch the releases from the provider API
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
          Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
          return result_lines unless response.status == 200

          # Parse the JSON response
          releases = JSON.parse(response.body).fetch("versions", [])

          # Extract version names and release dates into result_lines
          releases.each do |release|
            result_lines << GitTagWithDetail.new(
              tag: release["id"],
              release_date: release["published"]
            )
          end
          # Sort the result lines by tag in descending order
          result_lines.sort_by(&:tag).reverse
        end

        sig { returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped])) }
        def dependency_source_details
          return nil unless @dependency.source_details

          @dependency.source_details(allowed_types: ELIGIBLE_SOURCE_TYPES)
        end
      end
    end
  end
end
