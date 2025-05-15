# typed: true
# frozen_string_literal: true

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/bundler/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/bundler/update_checker/latest_version_finder/" \
        "dependency_source"
require "sorbet-runtime"

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        def initialize(dependency:, dependency_files:, repo_contents_path: nil,
                       credentials:, ignored_versions:, raise_on_ignored: false,
                       security_advisories:, options:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @repo_contents_path  = repo_contents_path
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
          @options             = options
        end

        def latest_version_details
          @latest_version_details ||= fetch_latest_version_details
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :repo_contents_path
        attr_reader :credentials
        attr_reader :ignored_versions
        attr_reader :security_advisories
        attr_reader :options

        def fetch_latest_version_details
          return dependency_source.latest_git_version_details if dependency_source.git?

          relevant_versions = dependency_source.versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)

          relevant_versions.empty? ? nil : { version: relevant_versions.max }
        end

        def fetch_lowest_security_fix_version
          return if dependency_source.git?

          relevant_versions = dependency_source.versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(relevant_versions,
                                                                                                    security_advisories)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min
        end

        sig { params(versions_array: T::Array[Gem::Version]).returns(T::Array[Gem::Version]) }
        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          filtered = versions_array.reject(&:prerelease?)
          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} pre-release versions")
          end
          filtered
        end

        sig { params(versions_array: T::Array[Gem::Version]).returns(T::Array[Gem::Version]) }
        def filter_ignored_versions(versions_array)
          filtered = versions_array
                     .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} ignored versions")
          end

          filtered
        end

        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array
            .select { |version| version > dependency.numeric_version }
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

        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
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
