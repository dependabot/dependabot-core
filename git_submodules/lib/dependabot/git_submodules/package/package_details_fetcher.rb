# typed: strict
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

          @ref = T.let(ref, String)
          @url = T.let(url, String)
        end

        # as git submodules do not have versions (refs/tags are used instead), we use a pseudo version as placeholder
        VERSION = "1.0.0"

        # we use a default release date in case we reply on fallback logic of
        # getting refs/tags to prevent filtering out head release (greater than max cooldown period)
        DEFAULT_RELEASE_DATE = T.let(Time.now.utc - (60 * 60 * 24 * 91), Time)

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          versions_metadata = T.let(fetch_tags_and_release_date, T.nilable(T::Array[GitTagWithDetail]))

          # we fallback to the git based tag info if no versions metadata is available
          if versions_metadata&.empty?
            versions_metadata = T.let(fetch_latest_tag_info,
                                      T.nilable(T::Array[GitTagWithDetail]))
          end

          releases = T.must(versions_metadata).map do |version_details|
            Dependabot::Package::PackageRelease.new(
              version: GitSubmodules::Version.new(VERSION),
              tag: version_details.tag,
              released_at: Time.parse(version_details.release_date)
            )
          end

          releases
        end

        private

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_latest_tag_info
          parsed_results = T.let([], T::Array[GitTagWithDetail])

          git_commit_checker = Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )

          parsed_results <<
            GitTagWithDetail.new(
              tag: T.must(git_commit_checker.head_commit_for_current_branch),
              release_date: DEFAULT_RELEASE_DATE.to_s
            )

          parsed_results
        end

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[GitTagWithDetail])

          begin
            Dependabot.logger.info("Fetching release info for Git Submodules: #{dependency.name}")

            response = Excon.get(provider_url)

            unless response.status == 200
              Dependabot.logger.error("Error while fetching details for #{dependency.name}" \
                                      " Detail : #{response.body}")
            end

            return parsed_results unless response.status == 200

            releases = JSON.parse(response.body)

            parsed_results = releases.map do |release|
              GitTagWithDetail.new(
                tag: release["sha"],
                release_date: release["commit"]["committer"]["date"]
              )
            end

            parsed_results
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for Git Submodules: #{e.message}")
            parsed_results
          end
        end

        sig { returns(String) }
        def provider_url
          provider_url = @url.gsub(/\.git$/, "")

          api_url = {
            github: provider_url.gsub("github.com", "api.github.com/repos")
          }.freeze

          "#{api_url[:github]}/commits?sha=#{@ref}"
        end

        sig { returns(String) }
        def ref
          dependency.source_details&.fetch(:ref, nil) ||
            dependency.source_details&.fetch(:branch, nil) || "HEAD"
        end

        sig { returns(String) }
        def url
          dependency.source_details&.fetch(:url, nil)
        end
      end
    end
  end
end
