# frozen_string_literal: true

require "json"
require "yaml"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/shared_helpers"
require "dependabot/pub/requirements_updater"
require "dependabot/pub/requirement"
require "dependabot/pub/version"

module Dependabot
  module Pub
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        return latest_version_for_git_dependency if git_dependency?
        return latest_version_for_hosted_dependency if hosted_dependency?
        # Other sources (path dependencies) just return `nil`
      end

      def latest_resolvable_version
        version = latest_version if git_dependency?
        version = latest_resolvable_version_for_hosted_dependency if hosted_dependency?

        return version unless version == dependency.version
        # Other sources (path dependencies) just return `nil`
      end

      def latest_resolvable_version_with_no_unlock
        latest_resolvable_version
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: latest_version,
          update_strategy: requirements_update_strategy,
          tag_for_latest_version: tag_for_latest_version,
          commit_hash_for_latest_version: commit_hash_for_latest_version
        ).updated_requirements
      end

      def requirements_update_strategy
        # If passed in as an option (in the base class) honour that option
        return @requirements_update_strategy.to_sym if @requirements_update_strategy

        # Otherwise, widen ranges for libraries and bump versions for apps
        library? ? :widen_ranges : :bump_versions
      end

      def requirement_class
        Requirement
      end

      def version_class
        Version
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # TODO: consider if multi version updates are easily doable with `dart pub outdated`.
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_for_hosted_dependency
        return unless hosted_dependency?

        return @latest_version_for_hosted_dependency if @latest_version_for_hosted_dependency

        versions = hosted_package_versions

        @latest_version_for_hosted_dependency = version_class.new(versions["latest"]["version"])
      end

      def latest_resolvable_version_for_hosted_dependency
        return unless hosted_dependency?

        return @latest_resolvable_version_for_hosted_dependency if @latest_resolvable_version_for_hosted_dependency

        versions = hosted_package_versions

        @latest_resolvable_version_for_hosted_dependency = version_class.new(versions["upgradable"]["version"])
      end

      def hosted_package_versions
        packages = packages_information["packages"]
        package = packages.find { |p| p["package"] == dependency.name }
        package
      end

      def latest_version_for_git_dependency
        # If the module isn't pinned then there's nothing for us to update
        # (since there's no lockfile to update the version in). We still
        # return the latest commit for the given branch, in order to keep
        # this method consistent
        return git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag that looks like a version then
        # we want to update that tag. Because we don't have a lockfile, the
        # latest version is the tag itself.
        if git_commit_checker.pinned_ref_looks_like_version?
          latest_tag = git_commit_checker.local_tag_for_latest_version&.
                       fetch(:tag)
          version_rgx = GitCommitChecker::VERSION_REGEX
          return unless latest_tag.match(version_rgx)

          version = latest_tag.match(version_rgx).
                    named_captures.fetch("version")
          return version_class.new(version)
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        nil
      end

      def tag_for_latest_version
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        latest_tag = git_commit_checker.local_tag_for_latest_version&.
                     fetch(:tag)

        version_rgx = GitCommitChecker::VERSION_REGEX
        return unless latest_tag.match(version_rgx)

        latest_tag
      end

      def commit_hash_for_latest_version
        return unless git_commit_checker.git_dependency?
        return unless git_commit_checker.pinned?
        return unless git_commit_checker.pinned_ref_looks_like_version?

        latest_commit_hash = git_commit_checker.local_tag_for_latest_version&.
                     fetch(:commit_sha)
        latest_tag = git_commit_checker.local_tag_for_latest_version&.
                     fetch(:tag)

        version_rgx = GitCommitChecker::VERSION_REGEX
        return unless latest_tag.match(version_rgx)

        latest_commit_hash
      end

      def library?
        # pubspec = YAML.safe_load(pubspec_files.fetch(:yaml).content)
        # Assume that a library does not have publish_to: none set, apps should set this.
        # TODO: Check this later how to deal with it
        @library = false # pubspec["publish_to"] != "none"
      end

      def hosted_dependency?
        return false if dependency_source_details.nil?

        dependency_source_details.fetch(:type) == "hosted"
      end

      def dependency_source_details
        sources =
          dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            requirement_class: Requirement,
            version_class: Version
          )
      end

      def packages_information
        # TODO: Consider replacing with pub API call.
        SharedHelpers.in_a_temporary_directory do
          File.write(pubspec_files.fetch(:yaml).name, pubspec_files.fetch(:yaml).content)
          File.write(pubspec_files.fetch(:lock).name, pubspec_files.fetch(:lock).content)

          SharedHelpers.with_git_configured(credentials: credentials) do
            output = SharedHelpers.run_shell_command("pub outdated --show-all --json")
            result = JSON.parse(output)
            result
          end
        end
      end

      def pubspec_files
        pubspec_file_pairs.first
      end

      def pubspec_file_pairs
        pairs = []
        pubspec_yaml_files.each do |f|
          lock_file = pubspec_lock_files.find { |l| f.directory == l.directory }
          next unless lock_file

          pairs << {
            yaml: f,
            lock: lock_file
          }
        end
        pairs
      end

      def pubspec_yaml_files
        dependency_files.select { |f| f.name.end_with?("pubspec.yaml") }
      end

      def pubspec_lock_files
        dependency_files.select { |f| f.name.end_with?("pubspec.lock") }
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("pub", Dependabot::Pub::UpdateChecker)
