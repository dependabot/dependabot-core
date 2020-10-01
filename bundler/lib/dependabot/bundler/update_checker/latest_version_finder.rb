# frozen_string_literal: true

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/bundler/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/bundler/update_checker/latest_version_finder/" \
        "dependency_source"

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder
        def initialize(dependency:, dependency_files:, repo_contents_path: nil,
                       credentials:, ignored_versions:, raise_on_ignored: false,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @repo_contents_path  = repo_contents_path
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
        end

        def latest_version_details
          @latest_version_details ||= fetch_latest_version_details
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency, :dependency_files, :repo_contents_path,
                    :credentials, :ignored_versions, :security_advisories

        def fetch_latest_version_details
          if dependency_source.git?
            return dependency_source.latest_git_version_details
          end

          relevant_versions = dependency_source.versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)

          relevant_versions.empty? ? nil : { version: relevant_versions.max }
        end

        def fetch_lowest_security_fix_version
          return if dependency_source.git?

          relevant_versions = dependency_source.versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_vulnerable_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min
        end

        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          versions_array.reject(&:prerelease?)
        end

        def filter_ignored_versions(versions_array)
          filtered = versions_array.
                     reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filtered.empty? && versions_array.any?
            raise AllVersionsIgnored
          end

          filtered
        end

        def filter_vulnerable_versions(versions_array)
          versions_array.
            reject { |v| security_advisories.any? { |a| a.vulnerable?(v) } }
        end

        def filter_lower_versions(versions_array)
          versions_array.
            select { |version| version > Gem::Version.new(dependency.version) }
        end

        def wants_prerelease?
          @wants_prerelease ||=
            begin
              current_version = dependency.version
              if current_version && Gem::Version.correct?(current_version) &&
                 Gem::Version.new(current_version).prerelease?
                return true
              end

              dependency.requirements.any? do |req|
                req[:requirement].match?(/[a-z]/i)
              end
            end
        end

        def dependency_source
          @dependency_source ||= DependencySource.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
        end

        def ignore_reqs
          ignored_versions.map { |req| Gem::Requirement.new(req.split(",")) }
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end
      end
    end
  end
end
