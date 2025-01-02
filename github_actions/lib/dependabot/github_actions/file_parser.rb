# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/github_actions/constants"
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

        dependencies_without_version = dependency_set.dependencies.select { |dep| dep.version.nil? }
        unless dependencies_without_version.empty?
          raise UnresolvableVersionError,
                dependencies_without_version.map(&:name)
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
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::GithubActions::PackageManager))
      end

      sig { params(file: Dependabot::DependencyFile).returns(Dependabot::FileParsers::Base::DependencySet) }
      def workfile_file_dependencies(file)
        dependency_set = DependencySet.new

        json = YAML.safe_load(T.must(file.content), aliases: true, permitted_classes: [Date, Time, Symbol])
        return dependency_set if json.nil?

        uses_strings = deep_fetch_uses(json.fetch("jobs", json.fetch("runs", nil))).uniq

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
        unless source&.hostname == GITHUB_COM
          dep = github_dependency(file, string, T.must(source).hostname)
          git_checker = Dependabot::GitCommitChecker.new(dependency: dep, credentials: credentials)
          return dep if git_checker.git_repo_reachable?
        end

        github_dependency(file, string, GITHUB_COM)
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
          package_manager: PackageManager::PACKAGE_MANAGER
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
