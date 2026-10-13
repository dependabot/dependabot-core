# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/experiments"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/workflow_file"

module Dependabot
  module GithubActions
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(MANIFEST_FILE_PATTERN) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a .github/workflows directory with YAML files or an action.yml file"
      end

      sig do
        override
          .params(
            source: Dependabot::Source,
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            options: T::Hash[Symbol, Object],
            update_config: T.nilable(Dependabot::Config::UpdateConfig)
          )
          .void
      end
      def initialize(source:, credentials:, repo_contents_path: nil, options: {}, update_config: nil)
        @workflow_files = T.let([], T::Array[DependencyFile])
        super
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_workflow_files

        if fetched_files.any?
          # The lockfile is additive: it is only fetched alongside workflow files
          # and never activates the ecosystem on its own. Relocking also requires
          # every workflow to be materialized, so retain the workflow-only path if
          # an invalidly encoded workflow had to be omitted.
          fetched_files += relock_files if incorrectly_encoded_workflow_files.empty?
          return fetched_files
        end

        if incorrectly_encoded_workflow_files.none?
          expected_paths =
            if directory == "/"
              File.join(directory, MANIFEST_FILE_YML) + " or /#{CONFIG_YMLS}"
            else
              File.join(directory, ANYTHING_YML)
            end

          raise(
            Dependabot::DependencyFileNotFound,
            expected_paths
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            T.must(incorrectly_encoded_workflow_files.first).path
          )
        end
      end

      private

      # The lockfile plus everything the engine needs to relock it, or nothing when
      # a workflow it would read is invalidly encoded.
      sig { returns(T::Array[DependencyFile]) }
      def relock_files
        lockfile = actions_lockfile
        return [] unless lockfile && repository_workflow_files.all? { |f| f.content&.valid_encoding? }

        [lockfile] + repository_workflow_files + self_repository_action_files
      end

      # Fetches the canonical `.github/workflows/actions.lock`. Composite-action
      # directories cannot own a lockfile, but `$/` workflows reaching them do.
      sig { returns(T.nilable(DependencyFile)) }
      def actions_lockfile
        return unless Dependabot::Experiments.enabled?(:github_actions_lockfile)
        return unless source.hostname == GITHUB_COM || source.hostname.end_with?(".ghe.com")

        fetch_file_if_present(relative_to_directory(LOCKFILE_PATH))
      end

      # Repository workflows a composite-action job needs to relock the lock. Support
      # files only: the composite job must never bump the workflows' own refs.
      sig { returns(T::Array[DependencyFile]) }
      def repository_workflow_files
        return [] if ["/", "/#{WORKFLOW_DIRECTORY}"].include?(File.join("/", directory))

        @repository_workflow_files ||= T.let(
          begin
            dir = relative_to_directory(WORKFLOW_DIRECTORY)
            repo_contents(dir: dir, raise_errors: false)
              .select { |f| f.type == "file" && f.name.match?(MANIFEST_FILE_PATTERN) }
              .map { |f| fetch_file_from_host(File.join(dir, f.name)) }
              .each { |f| f.support_file = true }
          end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(repo_path: String).returns(String) }
      def relative_to_directory(repo_path)
        Pathname.new(File.join("/", repo_path)).relative_path_from(File.join("/", directory)).to_s
      end

      # `$/` composites can live anywhere in the repo and can call each other, so
      # relocking needs every action definition, at its repo-relative path.
      sig { returns(T::Array[DependencyFile]) }
      def self_repository_action_files
        fetched = correctly_encoded_workflow_files + repository_workflow_files
        return [] unless fetched.any? { |f| self_repository_uses?(f) }

        # One recursive tree call. A truncated tree (>100k entries) may miss composites,
        # which the engine then reports as an EngineError.
        repo_action_paths
          .reject { |path| fetched.any? { |f| f.path == path } }
          .map do |path|
            file = fetch_file_from_host(relative_to_directory(path))
            file.support_file = true
            file
          end
      end

      sig { params(file: DependencyFile).returns(T::Boolean) }
      def self_repository_uses?(file)
        content = file.content.to_s
        return false unless content.include?("$/")

        WorkflowFile.new(content).uses_declarations.any? { |declaration| declaration.value.start_with?("$/") }
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        false
      end

      sig { returns(T::Array[String]) }
      def repo_action_paths
        tree = github_client.tree(repo, T.must(commit), recursive: true)
        T.let(tree[:tree], T::Array[Sawyer::Resource])
         .select { |entry| T.let(entry[:type], String) == "blob" }
         .map { |entry| T.let("/#{entry[:path]}", String) }
         .select { |path| ACTION_FILE_NAMES.include?(File.basename(path)) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def workflow_files
        return @workflow_files unless @workflow_files.empty?

        # In the special case where the root directory is defined we also scan
        # the .github/workflows/ folder.
        if directory == "/"
          @workflow_files += [
            fetch_file_if_present(MANIFEST_FILE_YML),
            fetch_file_if_present(MANIFEST_FILE_YAML)
          ].compact

          workflows_dir = WORKFLOW_DIRECTORY
        else
          workflows_dir = "."
        end

        @workflow_files +=
          repo_contents(dir: workflows_dir, raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(MANIFEST_FILE_PATTERN) }
          .map { |f| fetch_file_from_host("#{workflows_dir}/#{f.name}") }
      end

      sig { returns(T::Array[DependencyFile]) }
      def correctly_encoded_workflow_files
        workflow_files.select { |f| f.content&.valid_encoding? }
      end

      sig { returns(T::Array[DependencyFile]) }
      def incorrectly_encoded_workflow_files
        workflow_files.reject { |f| f.content&.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers
  .register("github_actions", Dependabot::GithubActions::FileFetcher)
