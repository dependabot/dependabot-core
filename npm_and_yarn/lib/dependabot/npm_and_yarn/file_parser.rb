# frozen_string_literal: true

# See https://docs.npmjs.com/files/package.json for package.json format docs.

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/helpers"
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

      def parse
        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies

        dependencies = Helpers.dependencies_with_all_versions_metadata(dependency_set)

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
              next unless requirement.is_a?(String)

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
        lockfile_parser.parse_set
      end

      def build_dependency(file:, type:, name:, requirement:)
        lockfile_details = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement,
          manifest_name: file.name
        )
        version = version_for(name, requirement, file.name)

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
            source: source_for(name, requirement, file.name)
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

      def version_for(name, requirement, manifest_name)
        if git_url_with_semver?(requirement)
          semver_version = semver_version_for(name, requirement, manifest_name)
          return semver_version if semver_version

          git_revision = git_revision_for(name, requirement, manifest_name)
          version_from_git_revision(requirement, git_revision) || git_revision
        elsif git_url?(requirement)
          git_revision_for(name, requirement, manifest_name)
        else
          semver_version_for(name, requirement, manifest_name)
        end
      end

      def git_revision_for(name, requirement, manifest_name)
        return unless git_url?(requirement)

        lockfile_details = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement,
          manifest_name: manifest_name
        )

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
          ).tags.
          select { |t| [t.commit_sha, t.tag_sha].include?(git_revision) }

        tags.each do |t|
          next unless t.name.match?(Dependabot::GitCommitChecker::VERSION_REGEX)

          version = t.name.match(Dependabot::GitCommitChecker::VERSION_REGEX).
                    named_captures.fetch("version")
          next unless version_class.correct?(version)

          return version
        end

        nil
      rescue Dependabot::GitDependenciesNotReachable
        nil
      end

      def semver_version_for(name, requirement, manifest_name)
        lock_version = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement,
          manifest_name: manifest_name
        )&.fetch("version", nil)

        # This line is to guard against improperly formatted versions in a
        # lockfile, such as additional characters. NPM/yarn fixes these when
        # running an update, so we can safely ignore these versions.
        return unless version_class.correct?(lock_version)

        lock_version
      end

      def source_for(name, requirement, manifest_name)
        return git_source_for(requirement) if git_url?(requirement)

        lockfile_details = lockfile_parser.lockfile_details(
          dependency_name: name,
          requirement: requirement,
          manifest_name: manifest_name
        )
        resolved_url = lockfile_details&.fetch("resolved", nil)

        resolution = lockfile_details&.fetch("resolution", nil)
        package_match = resolution&.match(/__archiveUrl=(?<package_url>.+)/)
        resolved_url = CGI.unescape(package_match.named_captures.fetch("package_url", "")) if package_match

        return unless resolved_url
        return unless resolved_url.start_with?("http")
        return if resolved_url.match?(/(?<!pkg\.)github/)

        registry_source_for(resolved_url, name)
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
                 prefix.split("git@").last.
                   sub(%r{.*?://}, "").
                   sub(%r{[:/]$}, "").
                   split("#").first
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

      def registry_source_for(resolved_url, name)
        url =
          if resolved_url.include?("/~/")
            # Gemfury format
            resolved_url.split("/~/").first
          elsif resolved_url.include?("/#{name}/-/#{name}")
            # MyGet / Bintray format
            resolved_url.split("/#{name}/-/#{name}").first.
              gsub("dl.bintray.com//", "api.bintray.com/npm/").
              # GitLab format
              gsub(%r{\/projects\/\d+}, "")
          elsif resolved_url.include?("/#{name}/-/#{name.split('/').last}")
            # Sonatype Nexus / Artifactory JFrog format
            resolved_url.split("/#{name}/-/#{name.split('/').last}").first
          elsif (cred_url = url_for_relevant_cred(resolved_url)) then cred_url
          else
            resolved_url.split("/")[0..2].join("/")
          end

        { type: "registry", url: url }
      end

      def url_for_relevant_cred(resolved_url)
        resolved_url_host = URI(resolved_url).host

        credential_matching_url =
          credentials.
          select { |cred| cred["type"] == "npm_registry" }.
          sort_by { |cred| cred["registry"].length }.
          find do |details|
            next true if resolved_url_host == details["registry"]

            uri = if details["registry"]&.include?("://")
                    URI(details["registry"])
                  else
                    URI("https://#{details['registry']}")
                  end
            resolved_url_host == uri.host
          end

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
              reject { |f| f.name.include?("node_modules/") }.
              reject(&:support_file?)

            [
              dependency_files.find { |f| f.name == "package.json" },
              *sub_packages
            ].compact
          end
      end

      def version_class
        NpmAndYarn::Version
      end
    end
  end
end

Dependabot::FileParsers.
  register("npm_and_yarn", Dependabot::NpmAndYarn::FileParser)
