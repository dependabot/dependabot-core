# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/github_actions/version"
require "dependabot/github_actions/package_manager"

# For docs, see
# https://help.github.com/en/articles/configuring-a-workflow#referencing-actions-in-your-workflow
# https://help.github.com/en/articles/workflow-syntax-for-github-actions#example-using-versioned-actions
module Dependabot
  module GithubActions
    class FileParser < Dependabot::FileParsers::Base
      extend T::Set

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        workflow_files.each do |file|
          dependency_set += workfile_file_dependencies(file)
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(begin
          # Extracts the `uses` name and `ref` (version) part from `uses` declarations in workflow files.
          # For example, in `actions/checkout@v2.3.4`, `uses_name` is "actions/checkout" and `ref` is "v2.3.4".
          # These pairs are collected from all `uses` keys across the workflow files.
          uses_info = workflow_files.flat_map do |file|
            json = YAML.safe_load(T.must(file.content), aliases: true, permitted_classes: [Date, Time, Symbol])
            next [] if json.nil?

            # Recursively fetch all `uses` strings from the JSON structure of the workflow file.
            uses_strings = deep_fetch_uses(json.fetch(JOBS_KEY, json.fetch(RUNS_KEY, nil))).uniq

            # Extract the `uses` name and `ref` part of the declaration,
            # if it matches the GitHub repository reference format.
            uses_strings.filter_map do |string|
              match = string.match(GITHUB_REPO_REFERENCE)
              next unless match

              # `match[:repo]` contains the name (e.g., "actions/checkout"), `match[:ref]`
              # contains the version (e.g., "v2.3.4").
              { name: match[:repo], version: match[:ref] }
            end
          end

          # Default to a placeholder if no uses information is found.
          default_info = { name: NO_DEPENDENCY_NAME, version: NO_VERSION }

          # Use the first `uses` info as the default or fallback to default_info.
          first_uses = uses_info.first || default_info

          # Initialize the PackageManager with the extracted name and version.
          PackageManager.new(first_uses[:name], first_uses[:version])
        end, T.nilable(Dependabot::GithubActions::PackageManager))
      end

      sig { params(file: Dependabot::DependencyFile).returns(Dependabot::FileParsers::Base::DependencySet) }
      def workfile_file_dependencies(file)
        dependency_set = DependencySet.new

        json = YAML.safe_load(T.must(file.content), aliases: true, permitted_classes: [Date, Time, Symbol])
        return dependency_set if json.nil?

        uses_strings = deep_fetch_uses(json.fetch(JOBS_KEY, json.fetch(RUNS_KEY, nil))).uniq

        uses_strings.each do |string|
          # TODO: Support Docker references and path references
          next if string.start_with?(".", "docker://")
          next unless string.match?(GITHUB_REPO_REFERENCE)

          dep = build_github_dependency(file, string)
          git_checker = Dependabot::GitCommitChecker.new(
            dependency: dep,
            credentials: credentials,
            consider_version_branches_pinned: true
          )
          if git_checker.git_repo_reachable?
            next unless git_checker.pinned?

            # If dep does not have an assigned (semver) version, look for a commit that references a semver tag
            unless dep.version
              resolved = git_checker.version_for_pinned_sha

              if resolved
                dep = Dependency.new(
                  name: dep.name,
                  version: resolved.to_s,
                  requirements: dep.requirements,
                  package_manager: dep.package_manager
                )
              end
            end
          end

          dependency_set << dep
        end

        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig { params(file: Dependabot::DependencyFile, string: String).returns(Dependabot::Dependency) }
      def build_github_dependency(file, string)
        unless source&.hostname == DOTCOM
          dep = github_dependency(file, string, T.must(source).hostname)
          git_checker = Dependabot::GitCommitChecker.new(dependency: dep, credentials: credentials)
          return dep if git_checker.git_repo_reachable?
        end

        github_dependency(file, string, DOTCOM)
      end

      sig { params(file: Dependabot::DependencyFile, string: String, hostname: String).returns(Dependabot::Dependency) }
      def github_dependency(file, string, hostname)
        details = T.must(string.match(GITHUB_REPO_REFERENCE)).named_captures
        name = "#{details.fetch(OWNER_KEY)}/#{details.fetch(REPO_KEY)}"
        ref = details.fetch(REF_KEY)
        version = version_class.new(ref).to_s if version_class.correct?(ref)
        Dependency.new(
          name: name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://#{hostname}/#{name}".downcase,
              ref: ref,
              branch: nil
            },
            file: file.name,
            metadata: { declaration_string: string }
          }],
          package_manager: PACKAGE_MANAGER
        )
      end

      sig { params(json_obj: T.untyped, found_uses: T::Array[String]).returns(T::Array[String]) }
      def deep_fetch_uses(json_obj, found_uses = [])
        case json_obj
        when Hash then deep_fetch_uses_from_hash(json_obj, found_uses)
        when Array then json_obj.flat_map { |o| deep_fetch_uses(o, found_uses) }
        else []
        end
      end

      sig { params(json_object: T::Hash[String, T.untyped], found_uses: T::Array[String]).returns(T::Array[String]) }
      def deep_fetch_uses_from_hash(json_object, found_uses)
        if json_object.key?(USES_KEY)
          found_uses << json_object[USES_KEY]
        elsif json_object.key?(STEPS_KEY)
          # Bypass other fields as uses are under steps if they exist
          deep_fetch_uses(json_object[STEPS_KEY], found_uses)
        else
          json_object.values.flat_map { |obj| deep_fetch_uses(obj, found_uses) }
        end

        found_uses
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def workflow_files
        # The file fetcher only fetches workflow files, so no need to
        # filter here
        dependency_files
      end

      sig { override.void }
      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No workflow files!"
      end

      sig { returns(T.class_of(Dependabot::GithubActions::Version)) }
      def version_class
        GithubActions::Version
      end
    end
  end
end

Dependabot::FileParsers
  .register("github_actions", Dependabot::GithubActions::FileParser)
