# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/resolvability_errors"
require "dependabot/go_modules/version"

module Dependabot
  module GoModules
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      RESOLVABILITY_ERROR_REGEXES = [
        # Package url/proxy doesn't include any redirect meta tags
        /no go-import meta tags/,
        # Package url 404s
        /404 Not Found/,
        /Repository not found/
      ].freeze

      def latest_resolvable_version
        # We don't yet support updating indirect dependencies for go_modules
        #
        # To update indirect dependencies we'll need to promote the indirect
        # dependency to the go.mod file forcing the resolver to pick this
        # version (possibly as `// indirect`)
        unless dependency.top_level?
          return unless dependency.version

          return version_class.new(dependency.version)
        end

        @latest_resolvable_version ||=
          version_class.new(find_latest_resolvable_version.gsub(/^v/, ""))
      end

      # This is currently used to short-circuit latest_resolvable_version,
      # with the assumption that it'll be quicker than checking
      # resolvability. As this is quite quick in Go anyway, we just alias.
      def latest_version
        latest_resolvable_version
      end

      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Go modules uses a single dependency file
        nil
      end

      def updated_requirements
        dependency.requirements.map do |req|
          req.merge(requirement: latest_version)
        end
      end

      private

      # TODO: Consider whether to retry failures
      def find_latest_resolvable_version
        pseudo_version_regex = /\b\d{14}-[0-9a-f]{12}$/
        return dependency.version if dependency.version =~ pseudo_version_regex

        SharedHelpers.in_a_temporary_directory do
          SharedHelpers.with_git_configured(credentials: credentials) do
            File.write("go.mod", go_mod.content)

            # Turn off the module proxy for now, as it's causing issues with private git dependencies
            env = { "GOPRIVATE" => "*" }

            json, stderr, status = Open3.capture3(env, SharedHelpers.escape_command("go list -m -versions --json #{dependency.name}"))
            if !status.success?
              # TODO: Should we populate an error_context here?
              handle_subprocess_error(SharedHelpers::HelperSubprocessFailed.new(message: stderr, error_context: {}))
            end

            version_strings = JSON.parse(json)["Versions"].select { |v| version_class.correct?(v) }

            # TODO Refactor
            current_version = version_class.new(dependency.version)
            candidate_versions = version_strings.map { |v| version_class.new(v) }
            prereleases, stable_releases = candidate_versions.partition { |v| v.prerelease? }
            latest = current_version.prerelease? ? prereleases.max : stable_releases.max
            "v#{latest}"
          end
        end
      end

      def handle_subprocess_error(error)
        if RESOLVABILITY_ERROR_REGEXES.any? { |rgx| error.message =~ rgx }
          ResolvabilityErrors.handle(error.message, credentials: credentials)
        end

        raise
      end

      def transitory_failure?(error)
        return true if error.message.include?("EOF")

        error.message.include?("Internal Server Error")
      end

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Go (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      # Override the base class's check for whether this is a git dependency,
      # since not all dep git dependencies have a SHA version (sometimes their
      # version is the tag)
      def existing_version_is_sha?
        git_dependency?
      end

      def library?
        dependency_files.none? { |f| f.type == "package_main" }
      end

      def version_from_tag(tag)
        # To compare with the current version we either use the commit SHA
        # (if that's what the parser picked up) or the tag name.
        return tag&.fetch(:commit_sha) if dependency.version&.match?(/^[0-9a-f]{40}$/)

        tag&.fetch(:tag)
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def default_source
        { type: "default", source: dependency.name }
      end

      def go_mod
        @go_mod ||= dependency_files.find { |f| f.name == "go.mod" }
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("go_modules", Dependabot::GoModules::UpdateChecker)
