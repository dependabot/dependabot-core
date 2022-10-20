# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/version"

module Dependabot
  module GoModules
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/latest_version_finder"

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

        latest_version_finder.latest_version
      end

      # This is currently used to short-circuit latest_resolvable_version,
      # with the assumption that it'll be quicker than checking
      # resolvability. As this is quite quick in Go anyway, we just alias.
      def latest_version
        latest_resolvable_version
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        unless dependency.top_level?
          return unless dependency.version

          return version_class.new(dependency.version)
        end

        lowest_security_fix_version
      end

      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
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

      def vulnerable?
        return super unless repo_contents_path

        # If we're not on a vulnerable range, let's not bother checking
        return false unless super

        directory = dependency_files.first.directory
        SharedHelpers.in_a_temporary_repo_directory(directory, repo_contents_path) do
          SharedHelpers.with_git_configured(credentials: credentials) do
            command = SharedHelpers.escape_command("govulncheck --json ./...")
            stdout, _, status = Open3.capture3(environment, command)
            # Fall back to original behavior
            return super unless status.success?

            res = JSON.parse(stdout) || {}

            # Considering us vulnerable if govulncheck finds any vulns that come
            # from the package in question. This should be improved by filtering
            # down to the right CVE, but this get's us going for now.
            res["Vulns"]&.any? { |v| v["ModPath"] == dependency.name }
          end
        end
      end

      private

      def latest_version_finder
        @latest_version_finder ||=
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            raise_on_ignored: raise_on_ignored,
            goprivate: options.fetch(:goprivate, "*")
          )
      end

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Go (yet)
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def environment
        { "GOPRIVATE" => @goprivate }
      end

      # Override the base class's check for whether this is a git dependency,
      # since not all dep git dependencies have a SHA version (sometimes their
      # version is the tag)
      def existing_version_is_sha?
        git_dependency?
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
