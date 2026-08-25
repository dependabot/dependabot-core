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
require "dependabot/github_actions/workflow_file"

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
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::GithubActions::PackageManager))
      end

      sig { params(file: Dependabot::DependencyFile).returns(Dependabot::FileParsers::Base::DependencySet) }
      def workfile_file_dependencies(file)
        dependency_set = DependencySet.new
        workflow_file = WorkflowFile.new(T.must(file.content))
        workflow_file.uses_declarations.group_by(&:value).each do |string, declarations|
          dep = dependency_for_declarations(file, workflow_file, string, declarations)
          next unless dep

          dependency_set << dep
        end
        dependency_set
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          workflow_file: WorkflowFile,
          string: String,
          declarations: T::Array[WorkflowFile::UsesDeclaration]
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def dependency_for_declarations(file, workflow_file, string, declarations)
        # TODO: Support Docker references and path references
        return if string.start_with?(".", "docker://")
        return unless string.match?(GITHUB_REPO_REFERENCE)

        metadata = declarations.map do |declaration|
          declaration_metadata(workflow_file, declaration)
        end
        dep = build_github_dependency(file, string, metadata)
        git_checker = Dependabot::GitCommitChecker.new(
          dependency: dep,
          credentials: credentials,
          consider_version_branches_pinned: true
        )
        return dep unless git_checker.git_repo_reachable?
        return unless git_checker.pinned?

        dependency_with_resolved_version(dep, git_checker) || dep
      end

      sig do
        params(
          workflow_file: WorkflowFile,
          declaration: WorkflowFile::UsesDeclaration
        ).returns(T::Hash[Symbol, Object])
      end
      def declaration_metadata(workflow_file, declaration)
        metadata = T.let({ declaration_string: declaration.value }, T::Hash[Symbol, Object])
        if workflow_file.source_metadata_required?(declaration)
          metadata[:yaml_source] = workflow_file.source_metadata(declaration)
        end
        metadata
      end

      sig do
        params(
          dep: Dependabot::Dependency,
          git_checker: Dependabot::GitCommitChecker
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def dependency_with_resolved_version(dep, git_checker)
        return if dep.version

        resolved = git_checker.version_for_pinned_sha
        return unless resolved

        Dependency.new(
          name: dep.name,
          version: resolved.to_s,
          requirements: dep.requirements,
          package_manager: dep.package_manager
        )
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          string: String,
          metadata: T::Array[T::Hash[Symbol, Object]]
        ).returns(Dependabot::Dependency)
      end
      def build_github_dependency(file, string, metadata)
        unless source&.hostname == GITHUB_COM
          dep = github_dependency(file, string, T.must(source).hostname, metadata)
          git_checker = Dependabot::GitCommitChecker.new(dependency: dep, credentials: credentials)
          return dep if git_checker.git_repo_reachable?
        end

        github_dependency(file, string, GITHUB_COM, metadata)
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          string: String,
          hostname: String,
          metadata: T::Array[T::Hash[Symbol, Object]]
        ).returns(Dependabot::Dependency)
      end
      def github_dependency(file, string, hostname, metadata)
        details = T.must(string.match(GITHUB_REPO_REFERENCE)).named_captures
        repo_name = "#{details.fetch(OWNER_KEY)}/#{details.fetch(REPO_KEY)}"
        path = details[PATH_KEY]
        ref = details.fetch(REF_KEY)
        version = version_class.new(ref).to_s if version_class.correct?(ref)

        # For reusable workflows (.github/workflows/*.yml), use the repository name + workflow path
        # to distinguish between different workflow files in the same repository
        name = if path&.match?(%r{/\.github/workflows/.*\.ya?ml$})
                 "#{repo_name}#{path}"
               elsif path && ref&.match?(/^[0-9a-f]{6,40}$/)
                 "#{repo_name}#{path}"
               elsif version_class.path_based?(ref)
                 string
               else
                 repo_name
               end
        Dependency.new(
          name: name,
          version: version,
          requirements: metadata.map do |details|
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://#{hostname}/#{repo_name}".downcase,
                ref: ref,
                branch: nil
              },
              file: file.name,
              metadata: details
            }
          end,
          package_manager: PackageManager::NAME
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def workflow_files
        dependency_files.reject { |file| file.path.delete_prefix("/") == LOCKFILE_PATH }
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
