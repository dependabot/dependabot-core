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
        (?<owner>[\w.-]+)/
        (?<repo>[\w.-]+)
        (?<path>/[^\@]+)?
        @(?<ref>.+)
      }x.freeze

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
        uses_strings = deep_fetch_uses(json).uniq

        uses_strings.each do |string|
          # TODO: Support Docker references and path references
          if string.match?(GITHUB_REPO_REFERENCE)
            dependency_set << build_github_dependency(file, string)
          end
        end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def build_github_dependency(file, string)
        details = string.match(GITHUB_REPO_REFERENCE).named_captures
        name = "#{details.fetch('owner')}/#{details.fetch('repo')}"
        url = "https://github.com/#{name}"

        Dependency.new(
          name: name,
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: url,
              ref: details.fetch("ref"),
              branch: nil
            },
            file: file.name,
            metadata: { declaration_string: string }
          }],
          package_manager: "github_actions"
        )
      end

      def deep_fetch_uses(json_obj)
        case json_obj
        when Hash then deep_fetch_uses_from_hash(json_obj)
        when Array then json_obj.flat_map { |o| deep_fetch_uses(o) }
        else []
        end
      end

      def deep_fetch_uses_from_hash(json_object)
        steps = json_object.fetch("steps", [])

        uses_strings =
          if steps.is_a?(Array) && steps.all? { |s| s.is_a?(Hash) }
            steps.
              map { |step| step.fetch("uses", nil) }.
              select { |use| use.is_a?(String) }
          else
            []
          end

        uses_strings +
          json_object.values.flat_map { |obj| deep_fetch_uses(obj) }
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
    end
  end
end

Dependabot::FileParsers.
  register("github_actions", Dependabot::GithubActions::FileParser)
