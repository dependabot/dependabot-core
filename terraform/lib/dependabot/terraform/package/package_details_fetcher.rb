# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "sorbet-runtime"
require "dependabot/swift"

module Dependabot
  module Terraform
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        RELEASES_URL_GIT = "https://api.github.com/repos/"
        RELEASE_URL_FOR_PROVIDER = "https://registry.terraform.io/v2/providers"
        RELEASE_URL_FOR_MODULE = "https://registry.terraform.io/v2/modules"
        APPLICATION_JSON = "JSON"
        INCLUDE_FOR_PROVIDER = "?include=provider-versions"
        INCLUDE_FOR_MODULE = "?include=module-versions"
        # https://registry.terraform.io/v2/providers/hashicorp/aws?include=provider-versions
        # https://registry.terraform.io/v2/modules/terraform-aws-modules/iam/aws?include=module-versions

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
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
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
          url = RELEASE_URL_FOR_PROVIDER + dependency_source_details&.fetch(:module_identifier) +
                INCLUDE_FOR_PROVIDER
          Dependabot.logger.info("Fetching provider release details from URL: #{url}")
          result_lines = T.let([], T::Array[GitTagWithDetail])
          # Fetch the releases from the provider API
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
          Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
          return result_lines unless response.status == 200

          # Parse the JSON response
          releases = JSON.parse(response.body).fetch("provider_versions", [])

          # Extract version names and release dates into result_lines
          releases.each do |release|
            result_lines << GitTagWithDetail.new(
              tag: release["version"],
              release_date: release["published_at"]
            )
          end
          # Sort the result lines by tag in descending order
          result_lines.sort_by(&:tag).reverse
        end

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date_from_module
          url = RELEASE_URL_FOR_MODULE + dependency_source_details&.fetch(:module_identifier) +
                INCLUDE_FOR_MODULE
          Dependabot.logger.info("Fetching provider release details from URL: #{url}")
          result_lines = T.let([], T::Array[GitTagWithDetail])
          # Fetch the releases from the provider API
          response = Excon.get(url, headers: { "Accept" => "application/vnd.github.v3+json" })
          Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
          return result_lines unless response.status == 200

          # Parse the JSON response
          releases = JSON.parse(response.body).fetch("module-versions", [])

          # Extract version names and release dates into result_lines
          releases.each do |release|
            result_lines << GitTagWithDetail.new(
              tag: release["version"],
              release_date: release["published_at"]
            )
          end
          # Sort the result lines by tag in descending order
          result_lines.sort_by(&:tag).reverse
        end

        sig { returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped])) }
        def dependency_source_details
          @dependency.source_details(allowed_types: ELIGIBLE_SOURCE_TYPES)
        end
      end
    end
  end
end
