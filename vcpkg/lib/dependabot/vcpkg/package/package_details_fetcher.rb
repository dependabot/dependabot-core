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
          fetch_port_versions_from_git
            .filter_map { |version_info| create_port_package_release(version_info) }
            .reverse
            .uniq(&:version)
            .then do |releases|
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases
            )
          end
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def fetch_port_versions_from_git
          port_path = "ports/#{dependency.name}/vcpkg.json"
          vcpkg_repo_path = "/opt/vcpkg"

          # Get each commit that modified the port's vcpkg.json
          git_log_cmd = [
            "git", "log", "--format=%H", "--follow", "--", port_path
          ]

          Dir.chdir(vcpkg_repo_path) do
            log_output = Dependabot::SharedHelpers.run_shell_command(git_log_cmd.join(" "))

            log_output.lines.map(&:strip).filter_map do |line|
              next if line.empty?

              commit_sha = line.strip
              next unless commit_sha.match?(/\A[0-9a-f]{40}\z/) # Validate SHA format

              # Get the vcpkg.json content for this commit
              version_info = extract_version_from_commit(commit_sha, port_path)
              version_info[:commit_sha] = commit_sha if version_info
              version_info
            end
          end
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          Dependabot.logger.warn("Failed to fetch port versions for #{dependency.name}: #{e.message}")
          []
        end

        sig { params(commit_sha: String, file_path: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def extract_version_from_commit(commit_sha, file_path)
          show_cmd = ["git", "show", "#{commit_sha}:#{file_path}"]

          file_content = Dependabot::SharedHelpers.run_shell_command(show_cmd.join(" "))
          parsed_json = JSON.parse(file_content)

          version = parsed_json["version"]
          port_version = parsed_json["port-version"] || 0

          return nil unless version

          # Combine version and port-version
          full_version = port_version.zero? ? version : "#{version}##{port_version}"

          {
            version: version,
            port_version: port_version,
            full_version: full_version,
            commit_date: get_commit_date(commit_sha)
          }
        rescue JSON::ParserError => e
          Dependabot.logger.warn("Failed to parse vcpkg.json for commit #{commit_sha}: #{e.message}")
          nil
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          Dependabot.logger.warn("Failed to show file #{file_path} for commit #{commit_sha}: #{e.message}")
          nil
        end

        sig { params(commit_sha: String).returns(T.nilable(Time)) }
        def get_commit_date(commit_sha)
          date_cmd = ["git", "show", "--no-patch", "--format=%ci", commit_sha]
          date_output = Dependabot::SharedHelpers.run_shell_command(date_cmd.join(" "))
          Time.parse(date_output.strip)
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          Dependabot.logger.warn("Failed to get commit date for #{commit_sha}: #{e.message}")
          nil
        rescue ArgumentError => e
          Dependabot.logger.warn("Invalid date format for commit #{commit_sha}: #{e.message}")
          nil
        end

        sig { params(tag_info: T::Hash[Symbol, T.untyped]).returns(Dependabot::Package::PackageRelease) }
        def create_registry_package_release(tag_info)
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new(tag_info.fetch(:tag)),
            tag: tag_info.fetch(:tag),
            url: dependency.source_details&.dig(:url),
            released_at: extract_release_date_from_tag(tag_info.fetch(:tag)),
            details: {
              "commit_sha" => tag_info.fetch(:commit_sha),
              "tag_sha" => tag_info.fetch(:tag_sha)
            }
          )
        end

        sig { params(version_info: T::Hash[Symbol, T.untyped]).returns(Dependabot::Package::PackageRelease) }
        def create_port_package_release(version_info)
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Vcpkg::Version.new(version_info.fetch(:full_version)),
            tag: version_info.fetch(:full_version),
            url: "#{Vcpkg::VCPKG_DEFAULT_BASELINE_URL}/tree/#{version_info[:commit_sha]}/ports/#{dependency.name}",
            released_at: version_info[:commit_date],
            details: {
              "commit_sha" => version_info[:commit_sha],
              "base_version" => version_info[:version],
              "port_version" => version_info[:port_version]
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
