# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

require "dependabot/git_commit_checker"
require "dependabot/package/package_details"
require "dependabot/registry_client"
require "dependabot/update_checkers/base"

require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch
          return unless git_dependency?

          Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: []
          ).local_tags_for_allowed_versions
                                      .map { |tag_info| create_package_release(tag_info) }
                                      .reverse
                                      .uniq(&:version)
                                      .then do |releases|
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases
            )
          end
        rescue Dependabot::GitDependenciesNotReachable
          # Fallback to empty releases if git repo is not reachable
          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: []
          )
        end

        private

        sig { returns(T::Boolean) }
        def git_dependency?
          dependency.source_details(allowed_types: ["git"]) in { type: "git" }
        end

        sig { params(tag_info: T::Hash[Symbol, T.untyped]).returns(Dependabot::Package::PackageRelease) }
        def create_package_release(tag_info)
          Dependabot::Package::PackageRelease.new(
            version: Version.new(tag_info.fetch(:tag)),
            tag: tag_info.fetch(:tag),
            url: dependency.source_details&.dig(:url),
            released_at: extract_release_date(tag_info.fetch(:tag)),
            details: {
              "commit_sha" => tag_info.fetch(:commit_sha),
              "tag_sha" => tag_info.fetch(:tag_sha)
            }
          )
        end

        sig { params(tag_name: String).returns(T.nilable(Time)) }
        def extract_release_date(tag_name)
          # Extract date from vcpkg tag format like "2025.06.13"
          # Use pattern matching for cleaner validation and extraction
          case tag_name.gsub(/^v?/, "")
          in /^(?<year>\d{4})\.(?<month>\d{2})\.(?<day>\d{2})$/
            begin
              Time.new($~[:year].to_i, $~[:month].to_i, $~[:day].to_i)
            rescue ArgumentError
              nil
            end
          else
            nil
          end
        end
      end
    end
  end
end
