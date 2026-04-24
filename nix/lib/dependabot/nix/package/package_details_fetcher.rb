# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"
require "dependabot/nix"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/git_commit_checker"
require "dependabot/git_metadata_fetcher"

module Dependabot
  module Nix
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
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          versions_metadata = fetch_tags_and_release_date

          versions_metadata = fetch_latest_tag_info if versions_metadata.empty?

          pseudo_version = versions_metadata.length + 1

          versions_metadata.flat_map do |version_details|
            pseudo_version -= 1
            tag = version_details[:tag]
            release_date = version_details[:release_date]

            Dependabot::Package::PackageRelease.new(
              version: Nix::Version.new("0.0.0-0.#{pseudo_version}"),
              tag: tag,
              released_at: release_date ? Time.parse(release_date) : nil
            )
          rescue ArgumentError
            Dependabot::Package::PackageRelease.new(
              version: Nix::Version.new("0.0.0-0.#{pseudo_version}"),
              tag: tag
            )
          end
        end

        private

        TARGET_COMMITS_TO_FETCH = 500
        private_constant :TARGET_COMMITS_TO_FETCH

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def fetch_latest_tag_info
          client = build_client
          head = client.head_commit_for_current_branch
          return [] unless head

          [{ tag: head }]
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

          begin
            Dependabot.logger.info("Fetching release info for Nix flake input: #{dependency.name}")
            client = build_client

            sha = T.let(nil, T.nilable(String))
            catch :found do
              while parsed_results.length < TARGET_COMMITS_TO_FETCH
                commits = get_commits(client, sha)
                break if commits.empty?

                commits.each do |commit|
                  sha = commit["sha"]
                  parsed_results << {
                    tag: sha,
                    release_date: commit.dig("commit", "committer", "date")
                  }
                  throw :found if sha == dependency.version
                end
                break if commits.length < Dependabot::GitMetadataFetcher::MAX_COMMITS_PER_PAGE
              end
            end
            parsed_results
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for nix flake input: #{e.message}")
            parsed_results
          end
        end

        sig { returns(Dependabot::GitCommitChecker) }
        def build_client
          Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
        end

        sig do
          params(
            client: Dependabot::GitCommitChecker,
            sha: T.nilable(String)
          ).returns(T::Array[T::Hash[String, T.untyped]])
        end
        def get_commits(client, sha)
          response = sha.nil? ? client.ref_details_for_pinned_ref : client.ref_details(sha)

          unless response.status == 200
            Dependabot.logger.error(
              "Error while fetching details for #{dependency.name}: #{response.body}"
            )
          end

          return [] unless response.status == 200

          commits = JSON.parse(response.body)
          sha.nil? || commits.empty? ? commits : commits[1..]
        rescue StandardError => e
          Dependabot.logger.error("Error fetching commits: #{e.message}")
          []
        end
      end
    end
  end
end
