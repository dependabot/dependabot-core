# frozen_string_literal: true

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/bundler/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder
        require_relative "shared_bundler_helpers"
        include SharedBundlerHelpers

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
        end

        def latest_version_details
          @latest_version_details ||= fetch_latest_version_details
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories

        def fetch_latest_version_details
          if dependency_source.is_a?(::Bundler::Source::Git) &&
             dependency.name != "bundler"
            return latest_git_version_details
          end

          relevant_versions = registry_versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)

          relevant_versions.empty? ? nil : { version: relevant_versions.max }
        end

        def fetch_lowest_security_fix_version
          return if dependency_source.is_a?(::Bundler::Source::Git)

          relevant_versions = registry_versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_vulnerable_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min
        end

        def filter_prerelease_versions(versions_array)
          versions_array.
            reject { |v| v.prerelease? && !wants_prerelease? }
        end

        def filter_ignored_versions(versions_array)
          versions_array.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }
        end

        def filter_vulnerable_versions(versions_array)
          arr = versions_array

          security_advisories.each do |advisory|
            arr = arr.reject { |v| advisory.vulnerable?(v) }
          end

          arr
        end

        def filter_lower_versions(versions_array)
          versions_array.
            select { |version| version > Gem::Version.new(dependency.version) }
        end

        def registry_versions
          return rubygems_versions if dependency.name == "bundler"
          return rubygems_versions unless dependency_source
          return [] unless dependency_source.is_a?(::Bundler::Source::Rubygems)

          remote = dependency_source.remotes.first
          return rubygems_versions if remote.nil?
          return rubygems_versions if remote.to_s == "https://rubygems.org/"

          private_registry_versions
        end

        def rubygems_versions
          @rubygems_versions ||=
            begin
              response = Excon.get(
                "https://rubygems.org/api/v1/versions/#{dependency.name}.json",
                idempotent: true,
                **SharedHelpers.excon_defaults
              )

              JSON.parse(response.body).
                map { |d| Gem::Version.new(d["number"]) }
            end
        rescue JSON::ParserError, Excon::Error::Timeout
          @rubygems_versions = []
        end

        def private_registry_versions
          @private_registry_versions ||=
            in_a_temporary_bundler_context do
              dependency_source.
                fetchers.flat_map do |fetcher|
                  fetcher.
                    specs_with_retry([dependency.name], dependency_source).
                    search_all(dependency.name)
                end.
                map(&:version)
            end
        end

        def latest_git_version_details
          dependency_source_details =
            dependency.requirements.map { |r| r.fetch(:source) }.
            uniq.compact.first

          in_a_temporary_bundler_context do
            SharedHelpers.with_git_configured(credentials: credentials) do
              # Note: we don't set `ref`, as we want to unpin the dependency
              source = ::Bundler::Source::Git.new(
                "uri" => dependency_source_details[:url],
                "branch" => dependency_source_details[:branch],
                "name" => dependency.name,
                "submodules" => true
              )

              # Tell Bundler we're fine with fetching the source remotely
              source.instance_variable_set(:@allow_remote, true)

              spec = source.specs.first
              { version: spec.version, commit_sha: spec.source.revision }
            end
          end
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
          return nil unless gemfile

          @dependency_source ||=
            in_a_temporary_bundler_context do
              definition = ::Bundler::Definition.build(gemfile.name, nil, {})

              specified_source =
                definition.dependencies.
                find { |dep| dep.name == dependency.name }&.source

              specified_source || definition.send(:sources).default_source
            end
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
