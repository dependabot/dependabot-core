# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package/package_details"
require "dependabot/package/package_release"
require "dependabot/lean"
require "dependabot/lean/version"

module Dependabot
  module Lean
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

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          releases = fetch_releases

          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: releases
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_releases
          github_releases.filter_map do |release|
            tag_name = T.let(release.tag_name, T.nilable(String))
            next unless tag_name&.start_with?("v")

            version_string = tag_name[1..] # Remove leading 'v'
            next unless version_string && Lean::Version.correct?(version_string)

            released_at = release.published_at ? Time.parse(release.published_at.to_s) : nil

            Dependabot::Package::PackageRelease.new(
              version: Lean::Version.new(version_string),
              released_at: released_at
            )
          end
        end

        sig { returns(T::Array[T.untyped]) }
        def github_releases
          @github_releases ||= T.let(
            fetch_all_releases,
            T.nilable(T::Array[T.untyped])
          )
        end

        sig { returns(T::Array[T.untyped]) }
        def fetch_all_releases
          # Fetch releases with pagination to get all of them
          all_releases = T.let([], T::Array[T.untyped])
          page = 1
          per_page = 100

          loop do
            releases = T.unsafe(github_client).releases(LEAN_GITHUB_REPO, per_page: per_page, page: page)
            break if releases.empty?

            all_releases.concat(releases)
            break if releases.length < per_page

            page += 1
            # Safety limit to avoid infinite loops
            break if page > 20
          end

          all_releases
        rescue Octokit::NotFound, Octokit::Forbidden => e
          Dependabot.logger.warn("Failed to fetch Lean releases: #{e.message}")
          []
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||= T.let(
            Dependabot::Clients::GithubWithRetries.for_source(
              source: github_source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
        end

        sig { returns(Dependabot::Source) }
        def github_source
          @github_source ||= T.let(
            Dependabot::Source.new(
              provider: "github",
              repo: LEAN_GITHUB_REPO,
              directory: nil,
              branch: nil
            ),
            T.nilable(Dependabot::Source)
          )
        end
      end
    end
  end
end
