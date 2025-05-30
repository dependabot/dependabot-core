# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/git_submodules"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module GitSubmodules
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, credentials:)
          @dependency = dependency
          @credentials = credentials

          @ref = dependency.source_details&.fetch(:ref, nil) ||
                 dependency.source_details&.fetch(:branch, nil) || "HEAD"
          @url = dependency&.source_details&.fetch(:url, nil)
        end

        # as git submodules do not have versions (refs/tags are used instead), we use a pseudo version as placeholder
        VERSION = "1.0.0"

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          versions_metadata = fetch_tags_and_release_date
          # we fallback to the git based tag info if no versions metadata is available
          versions_metadata = fetch_latest_tag_info if versions_metadata.empty?

          releases = versions_metadata.map do |version_details|
            Dependabot::Package::PackageRelease.new(
              version: GitSubmodules::Version.new(VERSION),
              tag: version_details[:tag],
              released_at: version_details[:release_date] ? Time.parse(version_details[:release_date]) : nil
            )
          end

          releases&.sort_by(&:released_at)
        end

        private

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_latest_tag_info
          parsed_results = T.let([], T::Array[GitTagWithDetail])

          git_commit_checker = Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )

          parsed_results << {
            tag: git_commit_checker.head_commit_for_current_branch,
            release_date: nil
          }
        end

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[GitTagWithDetail])
          begin
            response = Excon.get(provider_url)

            Dependabot.logger.error("Failed call details: #{response.body}") unless response.status == 200
            return parsed_results unless response.status == 200

            releases = JSON.parse(response.body)

            releases.map do |release|
              parsed_results << {
                tag: release["sha"],
                release_date: release["commit"]["committer"]["date"]
              }
            end

            parsed_results
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for GitSubmodules: #{e.message}")
            parsed_results
          end
        end

        def provider_url
          provider_url = @url&.gsub(/\.git$/, "")

          api_url = {
            github: provider_url.gsub("github.com", "api.github.com/repos")
          }.freeze

          "#{api_url[:github]}/commits?sha=#{@ref}"
        end
      end
    end
  end
end
