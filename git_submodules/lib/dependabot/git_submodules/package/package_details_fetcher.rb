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

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          versions_metadata = T.let(fetch_tags_and_release_date, T.nilable(T::Array[GitTagWithDetail]))

          # as git submodules do not have versions (refs/tags are used instead), we use a pseudo version as placeholder
          pseudo_version = 1.0

          # we fallback to the git based tag info if no versions metadata is available
          if versions_metadata&.empty?
            versions_metadata = T.let(fetch_latest_tag_info,
                                      T.nilable(T::Array[GitTagWithDetail]))
          end

          releases = T.must(versions_metadata).map do |version_details|
            Dependabot::Package::PackageRelease.new(
              version: GitSubmodules::Version.new((pseudo_version += 1).to_s),
              tag: version_details.tag,
              released_at: version_details.release_date ? Time.parse(T.must(version_details.release_date)) : nil
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
              tag: T.must(git_commit_checker.head_commit_for_current_branch)
            )

          parsed_results
        end

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[GitTagWithDetail])

          begin
            Dependabot.logger.info("Fetching release info for Git Submodules: #{dependency.name}")

            response = Dependabot::RegistryClient.get(url: provider_url)

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
            Dependabot.logger.error("Error while fetching package info for git submodule: #{e.message}")
            parsed_results
          end
        end

        sig { returns(String) }
        def provider_url
          provider_url = @url.gsub(/\.git$/, "")

          api_url = {
            github: provider_url.gsub("github.com", "api.github.com/repos")
          }.freeze

          "#{api_url[:github]}/commits?per_page=100&sha=#{@ref}"
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
