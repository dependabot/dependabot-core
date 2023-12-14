# typed: false
# frozen_string_literal: true

# See https://docs.npmjs.com/files/package.json for package.json format docs.

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/version"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/npm_and_yarn/registry_parser"
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
      GIT_URL_REGEX = %r{
        (?<git_prefix>^|^git.*?|^github:|^bitbucket:|^gitlab:|github\.com/)
        (?<username>[a-z0-9-]+)/
        (?<repo>[a-z0-9_.-]+)
        (
          (?:\#semver:(?<semver>.+))|
          (?:\#(?=[\^~=<>*])(?<semver>.+))|
          (?:\#(?<ref>.+))
        )?$
      }ix

      def self.each_dependency(json)
        DEPENDENCY_TYPES.each do |type|
          deps = json[type] || {}
          deps.each do |name, requirement|
            yield name, requirement, type
          end
        end
      end

      def parse
        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies

        dependencies = Helpers.dependencies_with_all_versions_metadata(dependency_set)

        dependencies.reject do |dep|
          reqs = dep.requirements

          # Ignore dependencies defined in support files, since we don't want PRs for those
          support_reqs = reqs.select { |r| support_package_files.any? { |f| f.name == r[:file] } }
          next true if support_reqs.any?

          # TODO: Currently, Dependabot can't handle dependencies that have both
          # a git source *and* a non-git source. Fix that!
          git_reqs = reqs.select { |r| r.dig(:source, :type) == "git" }
          next false if git_reqs.none?
          next true if git_reqs.map { |r| r.fetch(:source) }.uniq.count > 1

          dep.requirements.any? { |r| r.dig(:source, :type) != "git" }
        end
      end

      private

      def manifest_dependencies
        dependency_set = DependencySet.new

        package_files.each do |file|
          json = JSON.parse(file.content)

          # TODO: Currently, Dependabot can't handle flat dependency files
          # (and will error at the FileUpdater stage, because the
          # UpdateChecker doesn't take account of flat resolution).
          next if json["flat"]

          self.class.each_dependency(json) do |name, requirement, type|
            next unless requirement.is_a?(String)

            # Skip dependencies using Yarn workspace cross-references as requirements
            next if requirement.start_with?("workspace:")

            requirement = "*" if requirement == ""
            dep = build_dependency(
              file: file, type: type, name: name, requirement: requirement
            )
            dependency_set << dep if dep
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
        lockfile_parser.parse_set
      end

      def build_dependency(file:, type:, name:, requirement:)
        lockfile_details = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement,
          manifest_name: file.name
        )
        version = version_for(requirement, lockfile_details)

        return if lockfile_details && !version
        return if ignore_requirement?(requirement)
        return if workspace_package_names.include?(name)

        # TODO: Handle aliased packages:
        # https://github.com/dependabot/dependabot-core/pull/1115
        #
        # Ignore dependencies with an alias in the name
        # Example: "my-fetch-factory@npm:fetch-factory"
        return if aliased_package_name?(name)

        Dependency.new(
          name: name,
          version: version,
          package_manager: "npm_and_yarn",
          requirements: [{
            requirement: requirement_for(requirement),
            file: file.name,
            groups: [type],
            source: source_for(name, requirement, lockfile_details)
          }]
        )
      end

      def check_required_files
        raise "No package.json!" unless get_original_file("package.json")
      end

      def ignore_requirement?(requirement)
        return true if local_path?(requirement)
        return true if non_git_url?(requirement)

        # TODO: Handle aliased packages:
        # https://github.com/dependabot/dependabot-core/pull/1115
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

      def aliased_package_name?(name)
        name.include?("@npm:")
      end

      def workspace_package_names
        @workspace_package_names ||=
          package_files.filter_map { |f| JSON.parse(f.content)["name"] }
      end

      def version_for(requirement, lockfile_details)
        if git_url_with_semver?(requirement)
          semver_version = lockfile_version_for(lockfile_details)
          return semver_version if semver_version

          git_revision = git_revision_for(lockfile_details)
          version_from_git_revision(requirement, git_revision) || git_revision
        elsif git_url?(requirement)
          git_revision_for(lockfile_details)
        elsif lockfile_details
          lockfile_version_for(lockfile_details)
        else
          exact_version = exact_version_for(requirement)
          return unless exact_version

          semver_version_for(exact_version)
        end
      end

      def git_revision_for(lockfile_details)
        [
          lockfile_details&.fetch("version", nil)&.split("#")&.last,
          lockfile_details&.fetch("resolved", nil)&.split("#")&.last,
          lockfile_details&.fetch("resolved", nil)&.split("/")&.last
        ].find { |str| commit_sha?(str) }
      end

      def commit_sha?(string)
        return false unless string.is_a?(String)

        string.match?(/^[0-9a-f]{40}$/)
      end

      def version_from_git_revision(requirement, git_revision)
        tags =
          Dependabot::GitMetadataFetcher.new(
            url: git_source_for(requirement).fetch(:url),
            credentials: credentials
          ).tags
                                        .select { |t| [t.commit_sha, t.tag_sha].include?(git_revision) }

        tags.each do |t|
          next unless t.name.match?(Dependabot::GitCommitChecker::VERSION_REGEX)

          version = t.name.match(Dependabot::GitCommitChecker::VERSION_REGEX)
                     .named_captures.fetch("version")
          next unless version_class.correct?(version)

          return version
        end

        nil
      rescue Dependabot::GitDependenciesNotReachable
        nil
      end

      def lockfile_version_for(lockfile_details)
        semver_version_for(lockfile_details&.fetch("version", ""))
      end

      def semver_version_for(version)
        version_class.semver_for(version)
      end

      def exact_version_for(requirement)
        req = requirement_class.new(requirement)
        return unless req.exact?

        req.requirements.first.last.to_s
      rescue Gem::Requirement::BadRequirementError
        # If it doesn't parse, it's definitely not exact
      end

      def source_for(name, requirement, lockfile_details)
        return git_source_for(requirement) if git_url?(requirement)

        resolved_url = lockfile_details&.fetch("resolved", nil)

        resolution = lockfile_details&.fetch("resolution", nil)
        package_match = resolution&.match(/__archiveUrl=(?<package_url>.+)/)
        resolved_url = CGI.unescape(package_match.named_captures.fetch("package_url", "")) if package_match

        return unless resolved_url
        return unless resolved_url.start_with?("http")
        return if resolved_url.match?(/(?<!pkg\.)github/)

        RegistryParser.new(
          resolved_url: resolved_url,
          credentials: credentials
        ).registry_source_for(name)
      end

      def requirement_for(requirement)
        return requirement unless git_url?(requirement)

        details = requirement.match(GIT_URL_REGEX).named_captures
        details["semver"]
      end

      def git_source_for(requirement)
        details = requirement.match(GIT_URL_REGEX).named_captures
        prefix = details.fetch("git_prefix")

        host = if prefix.include?("git@") || prefix.include?("://")
                 prefix.split("git@").last
                       .sub(%r{.*?://}, "")
                       .sub(%r{[:/]$}, "")
                       .split("#").first
               elsif prefix.include?("bitbucket") then "bitbucket.org"
               elsif prefix.include?("gitlab") then "gitlab.com"
               else
                 "github.com"
               end

        {
          type: "git",
          url: "https://#{host}/#{details['username']}/#{details['repo']}",
          branch: nil,
          ref: details["ref"] || "master"
        }
      end

      def support_package_files
        @support_package_files ||= sub_package_files.select(&:support_file?)
      end

      def sub_package_files
        @sub_package_files ||=
          dependency_files.select { |f| f.name.end_with?("package.json") }
                          .reject { |f| f.name == "package.json" }
                          .reject { |f| f.name.include?("node_modules/") }
      end

      def package_files
        @package_files ||=
          [
            dependency_files.find { |f| f.name == "package.json" },
            *sub_package_files
          ].compact
      end

      def version_class
        NpmAndYarn::Version
      end

      def requirement_class
        NpmAndYarn::Requirement
      end
    end
  end
end

Dependabot::FileParsers
  .register("npm_and_yarn", Dependabot::NpmAndYarn::FileParser)
