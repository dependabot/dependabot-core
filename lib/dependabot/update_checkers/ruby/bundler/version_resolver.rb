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
        class VersionResolver
          require_relative "latest_version_finder"
          require_relative "shared_bundler_helpers"
          include SharedBundlerHelpers

          GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/

          def initialize(dependency:, dependency_files:, credentials:,
                         ignored_versions:)
            @dependency       = dependency
            @dependency_files = dependency_files
            @credentials      = credentials
            @ignored_versions = ignored_versions
          end

          def latest_resolvable_version_details
            @latest_resolvable_version_details ||=
              fetch_latest_resolvable_version_details
          end

          private

          attr_reader :dependency, :dependency_files, :credentials,
                      :ignored_versions

          def fetch_latest_resolvable_version_details
            return latest_version_details unless gemfile

            in_a_temporary_bundler_context do
              dep = dependency_from_definition

              # If the dependency wasn't found in the definition, it's because
              # the Gemfile didn't import the gemspec. This is unusual, but
              # the correct behaviour if/when it happens is to behave as if
              # the repo was gemspec-only
              next latest_version_details unless dep

              # If the old Gemfile index was used then it won't have checked
              # Ruby compatibility. Fix that by doing the check manually (and
              # saying no update is possible if the Ruby version is a mismatch)
              next nil if ruby_version_incompatible?(dep)

              details = { version: dep.version }
              if dep.source.instance_of?(::Bundler::Source::Git)
                details[:commit_sha] = dep.source.revision
              end
              details
            end
          end

          def dependency_from_definition
            dependencies_to_unlock = [dependency.name]
            begin
              definition = build_definition(dependencies_to_unlock)
              definition.resolve_remotely!
            rescue ::Bundler::GemNotFound => error
              # Handle yanked dependencies
              raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)
              gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                         named_captures["name"]
              raise if dependencies_to_unlock.include?(gem_name)
              dependencies_to_unlock << gem_name
              retry
            rescue ::Bundler::HTTPError => error
              # Retry network errors
              attempt ||= 1
              attempt += 1
              raise if attempt > 3 || !error.message.include?("Network error")
              retry
            end

            definition.resolve.find { |d| d.name == dependency.name }
          end

          def ruby_version_incompatible?(dep)
            return false unless dep.source.is_a?(::Bundler::Source::Rubygems)
            fetcher = dep.source.fetchers.first.fetchers.first

            # It's only the old index we have a problem with
            return false unless fetcher.is_a?(::Bundler::Fetcher::Dependency)

            # If no Ruby version is specified, we don't have a problem
            return false unless ruby_version

            versions = Excon.get(
              "#{fetcher.fetch_uri}api/v1/versions/#{dependency.name}.json",
              idempotent: true,
              **SharedHelpers.excon_defaults
            )

            ruby_requirement =
              JSON.parse(versions.body).
              find { |details| details["number"] == dep.version.to_s }&.
              fetch("ruby_version", nil)

            # Give the benefit of the doubt if we can't find the version's
            # required Ruby version.
            return false unless ruby_requirement
            ruby_requirement = Utils::Ruby::Requirement.new(ruby_requirement)

            !ruby_requirement.satisfied_by?(ruby_version)
          rescue JSON::ParserError, Excon::Error::Socket, Excon::Error::Timeout
            # Give the benefit of the doubt if something goes wrong fetching
            # version details (could be that it's a private index, etc.)
            false
          end

          def build_definition(dependencies_to_unlock)
            ::Bundler::Definition.build(
              "Gemfile", lockfile&.name, gems: dependencies_to_unlock
            )
          end

          def ruby_version
            return nil unless gemfile
            @ruby_version ||= build_definition([]).ruby_version&.gem_version
          end

          def latest_version_details
            @latest_version_details ||=
              LatestVersionFinder.new(
                dependency: dependency,
                dependency_files: dependency_files,
                credentials: credentials,
                ignored_versions: ignored_versions
              ).latest_version_details
          end

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end
        end
      end
    end
  end
end
