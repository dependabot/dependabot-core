# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/pub/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/pub/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"
require "sorbet-runtime"

module Dependabot
  module Pub
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        include Dependabot::Pub::Package

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            options: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions: [],
                       security_advisories: [], options: {})
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
          @options = options
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def current_report
          @current_report ||= T.must(PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            options: options
          ).report.find { |d| d["name"] == dependency.name })
        end

        sig { returns(String) }
        def latest_version
          return @latest_version if @latest_version

          @latest_version = current_report["latest"]

          @latest_version
        end

        sig { returns(T.nilable(String)) }
        def latest_resolvable_version
          return @latest_resolvable_version if @latest_resolvable_version

          @latest_resolvable_version = current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
          @latest_resolvable_version
        end

        sig { returns(T.nilable(T.any(String, Dependabot::Version))) }
        def latest_resolvable_version_with_no_unlock
          return @latest_resolvable_version_with_no_unlock if @latest_resolvable_version_with_no_unlock

          @latest_resolvable_version_with_no_unlock = current_report["compatible"].find do |d|
            d["name"] == dependency.name
          end
          @latest_resolvable_version_with_no_unlock
        end

        sig { returns(T.untyped) }
        def latest_version_resolvable_with_full_unlock
          return @latest_version_resolvable_with_full_unlock if @latest_version_resolvable_with_full_unlock

          @latest_version_resolvable_with_full_unlock = current_report["multiBreaking"]
          @latest_version_resolvable_with_full_unlock
        end

        private

        sig do
          params(
            unparsed_version: String
          ).returns(String)
        end
        def cooldown_version(unparsed_version)
          @cooldown_version ||= T.let(PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            options: options
          ).package_details_metadata, T.nilable(T::Array[T::Hash[String, T.untyped]]))

          return unparsed_version if publish_date(@cooldown_version, unparsed_version).nil?

          publish_date = publish_date(@cooldown_version, unparsed_version)

          Dependabot.logger.info("Found version #{unparsed_version} with publish date #{publish_date}")

          unparsed_version
        end

        sig { returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_pub)
        end

        sig do
          params(version_details: T::Array[T::Hash[String, T.untyped]],
                 unparsed_version: String).returns(T.nilable(String))
        end
        def publish_date(version_details, unparsed_version)
          if version_details.empty?
            Dependabot.logger.info("No metadata found for #{dependency.name}")
            return nil
          end

          publish_date = version_details.find do |key|
            key.fetch(:version) == unparsed_version
          end&.fetch(:publish_date)

          publish_date
        rescue StandardError => e
          Dependabot.logger.error("Failed to parse publish date for \"#{dependency.name}\": #{e.message}")
          nil
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories
        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options
      end
    end
  end
end
