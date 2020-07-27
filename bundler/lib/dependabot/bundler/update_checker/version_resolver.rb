# frozen_string_literal: true

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class UpdateChecker
      class VersionResolver
        require_relative "file_preparer"
        require_relative "latest_version_finder"
        require_relative "shared_bundler_helpers"
        include SharedBundlerHelpers

        GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/.freeze

        def initialize(dependency:, unprepared_dependency_files:,
                       credentials:, ignored_versions:,
                       raise_on_ignored: false,
                       replacement_git_pin: nil, remove_git_source: false,
                       unlock_requirement: true,
                       latest_allowable_version: nil)
          @dependency                  = dependency
          @unprepared_dependency_files = unprepared_dependency_files
          @credentials                 = credentials
          @ignored_versions            = ignored_versions
          @raise_on_ignored            = raise_on_ignored
          @replacement_git_pin         = replacement_git_pin
          @remove_git_source           = remove_git_source
          @unlock_requirement          = unlock_requirement
          @latest_allowable_version    = latest_allowable_version
        end

        def latest_resolvable_version_details
          @latest_resolvable_version_details ||=
            fetch_latest_resolvable_version_details
        end

        private

        attr_reader :dependency, :unprepared_dependency_files, :credentials,
                    :ignored_versions, :replacement_git_pin,
                    :latest_allowable_version

        def remove_git_source?
          @remove_git_source
        end

        def unlock_requirement?
          @unlock_requirement
        end

        def dependency_files
          @dependency_files ||=
            FilePreparer.new(
              dependency: dependency,
              dependency_files: unprepared_dependency_files,
              replacement_git_pin: replacement_git_pin,
              remove_git_source: remove_git_source?,
              unlock_requirement: unlock_requirement?,
              latest_allowable_version: latest_allowable_version
            ).prepared_dependency_files
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def fetch_latest_resolvable_version_details
          return latest_version_details unless gemfile

          SharedHelpers.with_git_configured(credentials: credentials) do
            in_a_temporary_bundler_context do
              dep = dependency_from_definition

              # If the dependency wasn't found in the definition, but *is*
              # included in a gemspec, it's because the Gemfile didn't import
              # the gemspec. This is unusual, but the correct behaviour if/when
              # it happens is to behave as if the repo was gemspec-only.
              if dep.nil? && dependency.requirements.any?
                next latest_version_details
              end

              # Otherwise, if the dependency wasn't found it's because it is a
              # subdependency that was removed when attempting to update it.
              next nil if dep.nil?

              # If the dependency is Bundler itself then we can't trust the
              # version that has been returned (it's the version Dependabot is
              # running on, rather than the true latest resolvable version).
              next nil if dep.name == "bundler"

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
        rescue Dependabot::DependencyFileNotResolvable => e
          return if error_due_to_restrictive_upper_bound?(e)
          return if circular_dependency_at_new_version?(e)
          raise unless ruby_lock_error?(e)

          @gemspec_ruby_unlocked = true
          regenerate_dependency_files_without_ruby_lock && retry
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def circular_dependency_at_new_version?(error)
          return false unless error.message.include?("CyclicDependencyError")

          error.message.include?("'#{dependency.name}'")
        end

        def error_due_to_restrictive_upper_bound?(error)
          # We see this when the dependency doesn't appear in the lockfile and
          # has an overly restrictive upper bound that we've added, either due
          # to an ignore condition or us missing that a pre-release is required
          # (as another dependency places a pre-release requirement on the dep)
          return false if dependency.appears_in_lockfile?

          error.message.include?("#{dependency.name} ")
        end

        def ruby_lock_error?(error)
          return false unless error.message.include?(" for gem \"ruby\0\"")
          return false if @gemspec_ruby_unlocked

          dependency_files.any? { |f| f.name.end_with?(".gemspec") }
        end

        def regenerate_dependency_files_without_ruby_lock
          @dependency_files =
            FilePreparer.new(
              dependency: dependency,
              dependency_files: unprepared_dependency_files,
              replacement_git_pin: replacement_git_pin,
              remove_git_source: remove_git_source?,
              unlock_requirement: unlock_requirement?,
              latest_allowable_version: latest_allowable_version,
              lock_ruby_version: false
            ).prepared_dependency_files
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def dependency_from_definition(unlock_subdependencies: true)
          dependencies_to_unlock = [dependency.name]
          dependencies_to_unlock += subdependencies if unlock_subdependencies
          begin
            definition = build_definition(dependencies_to_unlock)
            definition.resolve_remotely!
          rescue ::Bundler::GemNotFound => e
            unlock_yanked_gem(dependencies_to_unlock, e) && retry
          rescue ::Bundler::HTTPError => e
            # Retry network errors
            attempt ||= 1
            attempt += 1
            raise if attempt > 3 || !e.message.include?("Network error")

            retry
          end

          dep = definition.resolve.find { |d| d.name == dependency.name }
          return dep if dep
          return if dependency.requirements.any? || !unlock_subdependencies

          # If no definition was found and we're updating a sub-dependency,
          # try again but without unlocking any other sub-dependencies
          dependency_from_definition(unlock_subdependencies: false)
        end

        # rubocop:enable Metrics/PerceivedComplexity

        def unlock_yanked_gem(dependencies_to_unlock, error)
          raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)

          gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                     named_captures["name"]
          raise if dependencies_to_unlock.include?(gem_name)

          dependencies_to_unlock << gem_name
        end

        def subdependencies
          # If there's no lockfile we don't need to worry about
          # subdependencies
          return [] unless lockfile

          all_deps =  ::Bundler::LockfileParser.new(sanitized_lockfile_body).
                      specs.map(&:name).map(&:to_s).uniq
          top_level = build_definition([]).dependencies.
                      map(&:name).map(&:to_s)

          all_deps - top_level
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

          # Give the benefit of the doubt if something goes wrong fetching
          # version details (could be that it's a private index, etc.)
          return false unless versions.status == 200

          ruby_requirement =
            JSON.parse(versions.body).
            find { |details| details["number"] == dep.version.to_s }&.
            fetch("ruby_version", nil)

          # Give the benefit of the doubt if we can't find the version's
          # required Ruby version.
          return false unless ruby_requirement

          ruby_requirement = Requirement.new(ruby_requirement)

          !ruby_requirement.satisfied_by?(ruby_version)
        rescue JSON::ParserError, Excon::Error::Socket, Excon::Error::Timeout
          # Give the benefit of the doubt if something goes wrong fetching
          # version details (could be that it's a private index, etc.)
          false
        end

        def build_definition(dependencies_to_unlock)
          # Note: we lock shared dependencies to avoid any top-level
          # dependencies getting unlocked (which would happen if they were
          # also subdependencies of the dependency being unlocked)
          ::Bundler::Definition.build(
            gemfile.name,
            lockfile&.name,
            gems: dependencies_to_unlock,
            lock_shared_dependencies: true
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
              ignored_versions: ignored_versions,
              raise_on_ignored: @raise_on_ignored,
              security_advisories: []
            ).latest_version_details
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        def sanitized_lockfile_body
          re = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
          lockfile.content.gsub(re, "")
        end
      end
    end
  end
end
