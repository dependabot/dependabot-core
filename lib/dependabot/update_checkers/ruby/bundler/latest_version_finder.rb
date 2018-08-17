# frozen_string_literal: true

require "bundler_definition_ruby_version_patch"
require "bundler_definition_bundler_version_patch"
require "bundler_git_source_patch"

require "excon"

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/utils/ruby/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class LatestVersionFinder
          require_relative "shared_bundler_helpers"
          include SharedBundlerHelpers

          def initialize(dependency:, dependency_files:, credentials:,
                         ignored_versions:)
            @dependency       = dependency
            @dependency_files = dependency_files
            @credentials      = credentials
            @ignored_versions = ignored_versions
          end

          def latest_version_details
            @latest_version_details ||= fetch_latest_version_details
          end

          private

          attr_reader :dependency, :dependency_files, :credentials,
                      :ignored_versions

          def fetch_latest_version_details
            if dependency.name == "bundler"
              return latest_rubygems_version_details
            end

            case dependency_source
            when NilClass then latest_rubygems_version_details
            when ::Bundler::Source::Rubygems
              if dependency_source.remotes.first.to_s == "https://rubygems.org/"
                latest_rubygems_version_details
              else
                latest_private_version_details
              end
            when ::Bundler::Source::Git then latest_git_version_details
            end
          end

          def latest_rubygems_version_details
            response = Excon.get(
              "https://rubygems.org/api/v1/versions/#{dependency.name}.json",
              idempotent: true,
              **SharedHelpers.excon_defaults
            )

            relevant_versions =
              JSON.parse(response.body).
              reject do |d|
                version = Gem::Version.new(d["number"])
                next true if version.prerelease? && !wants_prerelease?
                next true if ignore_reqs.any? { |r| r.satisfied_by?(version) }
                false
              end

            dep = relevant_versions.max_by { |d| Gem::Version.new(d["number"]) }
            return unless dep
            {
              version: Gem::Version.new(dep["number"]),
              sha: dep["sha"]
            }
          rescue JSON::ParserError, Excon::Error::Timeout
            nil
          end

          def latest_private_version_details
            in_a_temporary_bundler_context do
              spec =
                dependency_source.
                fetchers.flat_map do |fetcher|
                  fetcher.
                    specs_with_retry([dependency.name], dependency_source).
                    search_all(dependency.name).
                    reject { |s| s.version.prerelease? && !wants_prerelease? }.
                    reject do |s|
                      ignore_reqs.any? { |r| r.satisfied_by?(s.version) }
                    end
                end.
                max_by(&:version)
              spec.nil? ? nil : { version: spec.version }
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
                definition = ::Bundler::Definition.build("Gemfile", nil, {})

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
            dependency_files.find { |f| f.name == "Gemfile" }
          end
        end
      end
    end
  end
end
