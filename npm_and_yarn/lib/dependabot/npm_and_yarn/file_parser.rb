# frozen_string_literal: true

# See https://docs.npmjs.com/files/package.json for package.json format docs.

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/version"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_commit_checker"
require "dependabot/errors"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/lockfile_parser"

      DEPENDENCY_TYPES =
        %w(dependencies devDependencies optionalDependencies).freeze
      CENTRAL_REGISTRIES = %w(
        https://registry.npmjs.org
        http://registry.npmjs.org
        https://registry.yarnpkg.com
      ).freeze
      GIT_URL_REGEX = %r{
        (?:^|^git.*?|^github:|^bitbucket:|^gitlab:|github\.com/)
        (?<username>[a-z0-9-]+)/
        (?<repo>[a-z0-9_.-]+)
        (
          (?:\#semver:(?<semver>.+))|
          (?:\#(?=[\^~=<>*])(?<semver>.+))|
          (?:\#(?<ref>.+))
        )?$
      }ix.freeze

      def parse
        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies
        dependencies = dependency_set.dependencies

        # TODO: Currently, Dependabot can't handle dependencies that have both
        # a git source *and* a non-git source. Fix that!
        dependencies.reject do |dep|
          git_reqs =
            dep.requirements.select { |r| r.dig(:source, :type) == "git" }
          next false if git_reqs.none?
          next true if git_reqs.map { |r| r.fetch(:source) }.uniq.count > 1

          dep.requirements.any? { |r| r.dig(:source, :type) != "git" }
        end
      end

      private

      def manifest_dependencies
        dependency_set = DependencySet.new

        package_files.each do |file|
          # TODO: Currently, Dependabot can't handle flat dependency files
          # (and will error at the FileUpdater stage, because the
          # UpdateChecker doesn't take account of flat resolution).
          next if JSON.parse(file.content)["flat"]

          DEPENDENCY_TYPES.each do |type|
            deps = JSON.parse(file.content)[type] || {}
            deps.each do |name, requirement|
              requirement = "*" if requirement == ""
              dep = build_dependency(
                file: file, type: type, name: name, requirement: requirement
              )
              dependency_set << dep if dep
            end
          end
        end

        dependency_set
      end

      def lockfile_parser
        @lockfile_parser ||= LockfileParser.new(
          dependency_files: dependency_files
        )
      end

      def lockfile_dependencies
        DependencySet.new(lockfile_parser.parse)
      end

      def build_dependency(file:, type:, name:, requirement:)
        lockfile_details = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement
        )
        return if lockfile_details && !version_for(name, requirement)
        return if ignore_requirement?(requirement)
        return if workspace_package_names.include?(name)

        Dependency.new(
          name: name,
          version: version_for(name, requirement),
          package_manager: "npm_and_yarn",
          requirements: [{
            requirement: requirement_for(requirement),
            file: file.name,
            groups: [type],
            source: source_for(name, requirement)
          }]
        )
      end

      def check_required_files
        raise "No package.json!" unless get_original_file("package.json")
      end

      def ignore_requirement?(requirement)
        return true if local_path?(requirement)
        return true if non_git_url?(requirement)

        # TODO: Handle aliased packages
        alias_package?(requirement)
      end

      def local_path?(requirement)
        requirement.start_with?("link:", "file:", "/", "./", "../", "~/")
      end

      def alias_package?(requirement)
        requirement.start_with?("npm:")
      end

      def non_git_url?(requirement)
        requirement.include?("://") && !git_url?(requirement)
      end

      def git_url?(requirement)
        requirement.match?(GIT_URL_REGEX)
      end

      def git_url_with_semver?(requirement)
        return false unless git_url?(requirement)

        !requirement.match(GIT_URL_REGEX).named_captures.fetch("semver").nil?
      end

      def workspace_package_names
        @workspace_package_names ||=
          package_files.map { |f| JSON.parse(f.content)["name"] }.compact
      end

      def version_for(name, requirement)
        if git_url_with_semver?(requirement)
          semver_version = semver_version_for(name, requirement)
          return semver_version if semver_version

          git_revision = git_revision_for(name, requirement)
          version_from_git_revision(requirement, git_revision) || git_revision
        elsif git_url?(requirement)
          git_revision_for(name, requirement)
        else
          semver_version_for(name, requirement)
        end
      end

      def git_revision_for(name, requirement)
        return unless git_url?(requirement)

        lockfile_details = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement
        )
        lock_version = lockfile_details&.fetch("version", nil)
        lock_res = lockfile_details&.fetch("resolved", nil)

        return lock_version.split("#").last if lock_version&.include?("#")
        return lock_res.split("#").last if lock_res&.include?("#")

        if lock_res && lock_res.split("/").last.match?(/^[0-9a-f]{40}$/)
          return lock_res.split("/").last
        end

        nil
      end

      def version_from_git_revision(requirement, git_revision)
        tags =
          Dependabot::GitMetadataFetcher.new(
            url: git_source_for(requirement).fetch(:url),
            credentials: credentials
          ).tags.
          select { |t| [t.commit_sha, t.tag_sha].include?(git_revision) }

        tags.each do |t|
          next unless t.name.match?(Dependabot::GitCommitChecker::VERSION_REGEX)

          version = t.name.match(Dependabot::GitCommitChecker::VERSION_REGEX).
                    named_captures.fetch("version")
          next unless NpmAndYarn::Version.correct?(version)

          return version
        end

        nil
      rescue Dependabot::GitDependenciesNotReachable
        nil
      end

      def semver_version_for(name, requirement)
        lock_version = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement
        )&.fetch("version", nil)

        return unless lock_version
        return if lock_version.include?("://")
        return if lock_version.include?("file:")
        return if lock_version.include?("link:")
        return if lock_version.include?("#")

        lock_version
      end

      def source_for(name, requirement)
        return git_source_for(requirement) if git_url?(requirement)

        resolved_url = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement
        )&.fetch("resolved", nil)

        return unless resolved_url
        return unless resolved_url.start_with?("http")
        return if CENTRAL_REGISTRIES.any? { |u| resolved_url.start_with?(u) }
        return if resolved_url.include?("github")

        private_registry_source_for(resolved_url, name)
      end

      def requirement_for(requirement)
        return requirement unless git_url?(requirement)

        details = requirement.match(GIT_URL_REGEX).named_captures
        details["semver"]
      end

      def git_source_for(requirement)
        details = requirement.match(GIT_URL_REGEX).named_captures
        {
          type: "git",
          url: "https://github.com/#{details['username']}/#{details['repo']}",
          branch: nil,
          ref: details["ref"] || "master"
        }
      end

      def private_registry_source_for(resolved_url, name)
        url =
          if resolved_url.include?("/~/")
            # Gemfury format
            resolved_url.split("/~/").first
          elsif resolved_url.include?("/#{name}/-/#{name.split('/').last}")
            # Sonatype Nexus / Artifactory JFrog format
            resolved_url.split("/#{name}/-/#{name.split('/').last}").first
          elsif (cred_url = url_for_relevant_cred(resolved_url)) then cred_url
          else resolved_url.split("/")[0..2].join("/")
          end

        { type: "private_registry", url: url }
      end

      def url_for_relevant_cred(resolved_url)
        credential_matching_url =
          credentials.
          select { |cred| cred["type"] == "npm_registry" }.
          sort_by { |cred| cred["registry"].length }.
          find { |details| resolved_url.include?(details["registry"]) }

        return unless credential_matching_url

        # Trim the resolved URL so that it ends at the same point as the
        # credential registry
        reg = credential_matching_url["registry"]
        resolved_url.gsub(/#{Regexp.quote(reg)}.*/, "") + reg
      end

      def package_files
        @package_files ||=
          begin
            sub_packages =
              dependency_files.
              select { |f| f.name.end_with?("package.json") }.
              reject { |f| f.name == "package.json" }.
              reject(&:support_file?)

            [
              dependency_files.find { |f| f.name == "package.json" },
              *sub_packages
            ].compact
          end
      end
    end
  end
end

Dependabot::FileParsers.
  register("npm_and_yarn", Dependabot::NpmAndYarn::FileParser)
