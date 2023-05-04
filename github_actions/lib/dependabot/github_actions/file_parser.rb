# frozen_string_literal: true

require "yaml"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "dependabot/github_actions/version"

# For docs, see
# https://help.github.com/en/articles/configuring-a-workflow#referencing-actions-in-your-workflow
# https://help.github.com/en/articles/workflow-syntax-for-github-actions#example-using-versioned-actions
module Dependabot
  module GithubActions
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      GITHUB_REPO_REFERENCE = %r{
        ^(?<owner>[\w.-]+)/
        (?<repo>[\w.-]+)
        (?<path>/[^\@]+)?
        @(?<ref>.+)
      }x

      def parse
        dependency_set = DependencySet.new

        workflow_files.each do |file|
          dependency_set += workfile_file_dependencies(file)
        end

        dependency_set.dependencies
      end

      private

      def workfile_file_dependencies(file)
        dependency_set = DependencySet.new

        json = YAML.safe_load(file.content, aliases: true)
        return dependency_set if json.nil?

        uses_strings = deep_fetch_uses(json.fetch("jobs", json.fetch("runs", nil))).uniq

        uses_strings.each do |string|
          # TODO: Support Docker references and path references
          next unless string.match?(GITHUB_REPO_REFERENCE)

          dep = build_github_dependency(file, string)
          git_checker = Dependabot::GitCommitChecker.new(dependency: dep, credentials: credentials)
          next unless git_checker.pinned?

          # If dep does not have an assigned (semver) version, look for a commit that references a semver tag
          unless dep.version
            resolved = git_checker.local_tag_for_pinned_sha

            if resolved && version_class.correct?(resolved)
              dep = Dependency.new(
                name: dep.name,
                version: version_class.new(resolved).to_s,
                requirements: dep.requirements,
                package_manager: dep.package_manager
              )
            end
          end

          dependency_set << dep
        end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def build_github_dependency(file, string)
        unless source.hostname == "github.com"
          dep = github_dependency(file, string, source.hostname)
          git_checker = Dependabot::GitCommitChecker.new(dependency: dep, credentials: credentials)
          return dep if git_checker.git_repo_reachable?
        end

        github_dependency(file, string, "github.com")
      end

      def github_dependency(file, string, hostname)
        details = string.match(GITHUB_REPO_REFERENCE).named_captures
        name = "#{details.fetch('owner')}/#{details.fetch('repo')}"
        ref = details.fetch("ref")
        version = version_class.new(ref).to_s if version_class.correct?(ref)
        Dependency.new(
          name: name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://#{hostname}/#{name}",
              ref: ref,
              branch: nil
            },
            file: file.name,
            metadata: { declaration_string: string }
          }],
          package_manager: "github_actions"
        )
      end

      def deep_fetch_uses(json_obj, found_uses = [])
        case json_obj
        when Hash then deep_fetch_uses_from_hash(json_obj, found_uses)
        when Array then json_obj.flat_map { |o| deep_fetch_uses(o, found_uses) }
        else []
        end
      end

      def deep_fetch_uses_from_hash(json_object, found_uses)
        if json_object.key?("uses")
          found_uses << json_object["uses"]
        elsif json_object.key?("steps")
          # Bypass other fields as uses are under steps if they exist
          deep_fetch_uses(json_object["steps"], found_uses)
        else
          json_object.values.flat_map { |obj| deep_fetch_uses(obj, found_uses) }
        end

        found_uses
      end

      def workflow_files
        # The file fetcher only fetches workflow files, so no need to
        # filter here
        dependency_files
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No workflow files!"
      end

      def version_class
        GithubActions::Version
      end
    end
  end
end

Dependabot::FileParsers.
  register("github_actions", Dependabot::GithubActions::FileParser)
