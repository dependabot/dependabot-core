# typed: true
# frozen_string_literal: true

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/bundler/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/bundler/update_checker/latest_version_finder/" \
        "dependency_source"
require "sorbet-runtime"

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          ).fetch
        end

        def latest_version_details
          @latest_version_details ||= fetch_latest_version_details
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_bundler)
        end

        private

        def fetch_latest_version_details
          return dependency_source.latest_git_version_details if dependency_source.git?

          relevant_versions = dependency_source.versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)

          relevant_versions.empty? ? nil : { version: relevant_versions.max }
        end

        def fetch_lowest_security_fix_version(language_version: nil)
          return if dependency_source.git?

          relevant_versions = dependency_source.versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(relevant_versions,
                                                                                                    security_advisories)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min
        end

        def wants_prerelease?
          @wants_prerelease ||=
            begin
              current_version = dependency.numeric_version
              if current_version&.prerelease?
                true
              else
                dependency.requirements.any? do |req|
                  req[:requirement].match?(/[a-z]/i)
                end
              end
            end
        end

        def dependency_source
          @dependency_source ||= DependencySource.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            options: options
          )
        end

        def requirement_class
          dependency.requirement_class
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end
      end
    end
  end
end
