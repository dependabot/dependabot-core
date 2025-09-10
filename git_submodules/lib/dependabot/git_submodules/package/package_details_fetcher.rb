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

          @url = T.let(url, String)
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          sha_to_tags = build_sha_to_tags
          versions_metadata = T.let(fetch_tags_and_release_date, T.nilable(T::Array[GitTagWithDetail]))

          # we fallback to the git based tag info if no versions metadata is available
          if versions_metadata&.empty?
            versions_metadata = T.let(fetch_latest_tag_info,
                                      T.nilable(T::Array[GitTagWithDetail]))
          end

          # as git submodules do not have versions (refs/tags are used instead), we use a pseudo version as placeholder
          pseudo_version = T.must(versions_metadata).length + 1

          T.must(versions_metadata).flat_map do |version_details|
            process_metadata(version_details, sha_to_tags, pseudo_version -= 1)
          end
        end

        private

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_latest_tag_info
          parsed_results = T.let([], T::Array[GitTagWithDetail])

          git_commit_checker = build_client

          parsed_results <<
            GitTagWithDetail.new(
              tag: T.must(git_commit_checker.head_commit_for_current_branch)
            )

          parsed_results
        end

        TARGET_COMMITS_TO_FETCH = 250

        sig { returns(T::Array[GitTagWithDetail]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[GitTagWithDetail])

          begin
            Dependabot.logger.info("Fetching release info for Git Submodules: #{dependency.name}")
            client = build_client

            sha = T.let(nil, T.nilable(String))
            while parsed_results.length < TARGET_COMMITS_TO_FETCH
              max_len = Dependabot::GitMetadataFetcher::MAX_COMMITS_PER_PAGE
              max_len -= 1 unless sha.nil?
              commits = get_commits(client, sha)
              break if commits.empty?

              commits.each do |commit|
                sha = commit["sha"]
                parsed_results << GitTagWithDetail.new(
                  tag: sha,
                  release_date: commit["commit"]["committer"]["date"]
                )
              end
              break if commits.length < max_len

            end
            parsed_results
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for git submodule: #{e.message}")
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

        sig { returns(String) }
        def url
          dependency.source_details&.fetch(:url, nil)
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def build_sha_to_tags
          build_client.tags.each_with_object({}) do |tag, sha_to_tags|
            (sha_to_tags[tag.commit_sha] ||= []) << tag.name
          end
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
            Dependabot.logger.error("Error while fetching details for #{dependency.name} " \
                                    "Detail : #{response.body}")
          end

          return [] unless response.status == 200

          commits = JSON.parse(response.body)
          sha.nil? || commits.empty? ? commits : commits[1..]
        end

        sig do
          params(
            version_details: GitTagWithDetail,
            sha_to_tags: T::Hash[String, T::Array[String]],
            pseudo_version: Integer
          ).returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def process_metadata(version_details, sha_to_tags, pseudo_version)
          released_at = version_details.release_date ? Time.parse(T.must(version_details.release_date)) : nil
          sha = version_details.tag

          normalized_versions(sha, sha_to_tags, pseudo_version).map do |version|
            Dependabot::Package::PackageRelease.new(
              version: version,
              tag: sha,
              released_at: released_at
            )
          end
        end

        sig do
          params(
            sha: String,
            sha_to_tags: T::Hash[String, T::Array[String]],
            pseudo_version: Integer
          ).returns(T::Array[Dependabot::Version])
        end
        def normalized_versions(sha, sha_to_tags, pseudo_version)
          versions = Array(sha_to_tags[sha]).map do |tag_name|
            normalized_version(tag_name, pseudo_version)
          end

          versions << normalized_version(sha, pseudo_version)

          versions.uniq
        end

        sig { params(tag: String, pseudo_version: Integer).returns(Dependabot::Version) }
        def normalized_version(tag, pseudo_version)
          if Dependabot::Version.valid_semver?(tag)
            Dependabot::Version.new(tag)
          elsif tag.start_with?("v") && GitSubmodules::Version.valid_semver?(T.must(tag[1..]))
            Dependabot::Version.new(tag[1..])
          else
            Dependabot::Version.new("0.0.0-0.#{pseudo_version}")
          end
        end
      end
    end
  end
end
