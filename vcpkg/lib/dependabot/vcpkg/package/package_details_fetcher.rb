# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

require "dependabot/git_commit_checker"
require "dependabot/logger"
require "dependabot/package/package_details"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/base"

require "dependabot/vcpkg"
require "dependabot/vcpkg/package/versions_database"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            versions_database: Dependabot::Vcpkg::Package::VersionsDatabase
          ).void
        end
        def initialize(dependency:, versions_database: Dependabot::Vcpkg::Package::VersionsDatabase.new)
          @dependency = dependency
          @versions_database = versions_database
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::Vcpkg::Package::VersionsDatabase) }
        attr_reader :versions_database

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch
          if registry_dependency?
            fetch_registry_releases
          else
            fetch_port_releases
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
        def registry_dependency?
          dependency.source_details(allowed_types: ["git"]) in { type: "git" }
        end

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch_registry_releases
          Dependabot::GitCommitChecker
            .new(
              dependency: dependency,
              credentials: []
            )
            .local_tags_for_allowed_versions
            .map { |tag_info| create_registry_package_release(tag_info) }
            .reverse
            .uniq(&:version)
            .then do |releases|
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases
            )
          end
        end

        sig { returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def fetch_port_releases
          release_dates = versions_database.release_dates_for(dependency.name)

          releases = versions_database
                     .versions_for(dependency.name)
                     .map { |port_version| create_port_package_release(port_version, release_dates) }
                     .uniq(&:version)

          Dependabot::Package::PackageDetails.new(dependency: dependency, releases: releases)
        end

        sig { params(tag_info: T::Hash[Symbol, T.untyped]).returns(Dependabot::Package::PackageRelease) }
        def create_registry_package_release(tag_info)
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new(tag_info.fetch(:tag)),
            tag: tag_info.fetch(:tag),
            url: dependency.source_string("url"),
            released_at: extract_release_date_from_tag(tag_info.fetch(:tag)),
            details: {
              "commit_sha" => tag_info.fetch(:commit_sha),
              "tag_sha" => tag_info.fetch(:tag_sha)
            }
          )
        end

        sig do
          params(
            port_version: Dependabot::Vcpkg::Package::VersionsDatabase::PortVersion,
            release_dates: T::Hash[String, Time]
          ).returns(Dependabot::Package::PackageRelease)
        end
        def create_port_package_release(port_version, release_dates)
          version = port_version.version
          git_tree = port_version.git_tree

          Dependabot::Package::PackageRelease.new(
            version: version,
            tag: version.to_s,
            url: "#{Vcpkg::VCPKG_DEFAULT_REGISTRY_REPOSITORY}/tree/" \
                 "#{Vcpkg::VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH}/ports/#{dependency.name}",
            released_at: git_tree && release_dates[git_tree],
            details: {
              "scheme" => port_version.scheme,
              "base_version" => version.text,
              "port_version" => version.port_version,
              "git_tree" => git_tree
            }
          )
        end

        sig { params(tag_name: String).returns(T.nilable(Time)) }
        def extract_release_date_from_tag(tag_name)
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
