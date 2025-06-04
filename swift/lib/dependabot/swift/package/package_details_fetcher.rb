# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "sorbet-runtime"
require "dependabot/swift"

module Dependabot
  module Swift
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        RELEASES_URL = "https://api.github.com/repos/"
        APPLICATION_JSON = "JSON"

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
          url = RELEASES_URL + "#{truncate_github_url}/releases"
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
      end
    end
  end
end
