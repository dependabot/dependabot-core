# frozen_string_literal: true

require "excon"
require "dependabot/git_commit_checker"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

require "json"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex < Dependabot::UpdateCheckers::Base
        require_relative "hex/file_preparer"
        require_relative "hex/version"
        require_relative "hex/requirements_updater"
        require_relative "hex/version_resolver"

        def latest_version
          return latest_version_for_git_dependency if git_dependency?
          return latest_resolvable_version unless hex_registry_response

          latest_release_on_hex_registry
        end

        def latest_resolvable_version
          @latest_resolvable_version ||=
            if git_dependency?
              latest_resolvable_version_for_git_dependency
            else
              fetch_latest_resolvable_version(unlock_requirement: true)
            end
        end

        def latest_resolvable_version_with_no_unlock
          if git_dependency? && git_commit_checker.pinned?
            return dependency.version
          end

          @latest_resolvable_version_with_no_unlock ||=
            fetch_latest_resolvable_version(unlock_requirement: false)
        rescue SharedHelpers::HelperSubprocessFailed => error
          if error.message.include?("resolution failed") && git_dependency?
            return
          end
          raise error
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
        end

        def version_class
          Hex::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Elixir (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def latest_version_for_git_dependency
          latest_git_version_sha
        end

        def latest_resolvable_version_for_git_dependency
          # TODO: we should be updating the ref here if pinned to a
          # version-like ref. For now, this setup means we at least get
          # branch updates, though.
          fetch_latest_resolvable_version(unlock_requirement: false)
        rescue SharedHelpers::HelperSubprocessFailed => error
          return if error.message.include?("resolution failed")
          raise error
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def latest_git_version_sha
          # If the gem isn't pinned, the latest version is just the latest
          # commit for the specified branch.
          unless git_commit_checker.pinned?
            return git_commit_checker.head_commit_for_current_branch
          end

          # If the dependency is pinned to a tag that looks like a version then
          # we want to update that tag. The latest version will then be the SHA
          # of the latest tag that looks like a version.
          if git_commit_checker.pinned_ref_looks_like_version?
            latest_tag = git_commit_checker.local_tag_for_latest_version
            return latest_tag&.fetch(:tag_sha) || dependency.version
          end

          # If the dependency is pinned to a tag that doesn't look like a
          # version then there's nothing we can do.
          dependency.version
        end

        def fetch_latest_resolvable_version(unlock_requirement:)
          @latest_resolvable_version ||= {}
          @latest_resolvable_version[unlock_requirement] ||=
            version_resolver(unlock_requirement: unlock_requirement).
            latest_resolvable_version
        end

        def version_resolver(unlock_requirement:)
          @version_resolver ||= {}
          @version_resolver[unlock_requirement] ||=
            begin
              prepared_dependency_files = prepared_dependency_files(
                unlock_requirement: unlock_requirement
              )

              VersionResolver.new(
                dependency: dependency,
                dependency_files: prepared_dependency_files,
                credentials: credentials
              )
            end
        end

        def prepared_dependency_files(unlock_requirement:)
          FilePreparer.new(
            dependency: dependency,
            dependency_files: dependency_files,
            unlock_requirement: unlock_requirement
          ).prepared_dependency_files
        end

        def latest_release_on_hex_registry
          versions =
            hex_registry_response["releases"].
            select { |release| version_class.correct?(release["version"]) }.
            map { |release| version_class.new(release["version"]) }

          versions = versions.reject(&:prerelease?) unless wants_prerelease?
          versions.sort.last
        end

        def hex_registry_response
          return @hex_registry_response unless @hex_registry_response.nil?

          response = Excon.get(
            dependency_url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          return nil unless response.status == 200

          @hex_registry_response = JSON.parse(response.body)
        end

        def wants_prerelease?
          current_version = dependency.version
          if current_version &&
             version_class.correct?(current_version) &&
             version_class.new(current_version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            req[:requirement].match?(/\d-[A-Za-z0-9]/)
          end
        end

        def dependency_url
          "https://hex.pm/api/packages/#{dependency.name}"
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              github_access_token: github_access_token
            )
        end

        def github_access_token
          credentials.
            find { |cred| cred["host"] == "github.com" }.
            fetch("password")
        end
      end
    end
  end
end
