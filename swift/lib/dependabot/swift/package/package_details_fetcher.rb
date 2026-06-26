# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "excon"
require "sorbet-runtime"
require "dependabot/swift"
require "dependabot/swift/version"
require "dependabot/source"
require "dependabot/clients/github_with_retries"

module Dependabot
  module Swift
    module Package
      class PackageDetailsFetcher
        extend T::Sig

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

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tag_and_release_date
          source = source_from_dependency
          return [] unless source
          return [] unless source.provider == "github"

          client = Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )

          releases = client.releases(source.repo, per_page: 100)

          result_lines = T.let([], T::Array[GitTagWithDetail])
          releases.each do |release|
            next if release.prerelease

            tag_name = release.tag_name
            next unless tag_name.is_a?(String)

            normalized_tag = tag_name.delete_prefix("v")
            next unless Version.correct?(normalized_tag)

            published_at = release.published_at
            release_date = case published_at
                           when Time then published_at.iso8601
                           when String then published_at
                           end
            result_lines << GitTagWithDetail.new(
              tag: tag_name,
              release_date: release_date
            )
          end

          result_lines.sort_by do |detail|
            Version.new(detail.tag.delete_prefix("v"))
          end.reverse
        rescue Octokit::Error => e
          Dependabot.logger.debug("Error fetching release details: #{e.message}")
          []
        end

        private

        sig { returns(T.nilable(Dependabot::Source)) }
        def source_from_dependency
          url = "https://#{@dependency.name}"
          Dependabot::Source.from_url(url)
        end
      end
    end
  end
end
