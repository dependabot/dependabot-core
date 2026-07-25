# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/errors"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/logger"

require "dependabot/azure_pipelines/constants"

module Dependabot
  module AzurePipelines
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      YAML_PATTERN = T.let(/\.ya?ml$/i, Regexp)

      # Azure Pipelines has no required location or name for a pipeline: any YAML file
      # in the repository can be one, and templates are routinely kept in directories
      # of their own. Candidates are therefore recognised by shape rather than path,
      # which means opening them, so the search is bounded.
      MAX_DEPTH = T.let(3, Integer)
      MAX_CANDIDATES = T.let(200, Integer)

      # Listing a directory costs a request too, so a repository with thousands of
      # shallow directories would burn the rate limit before the file budget ever
      # came into play.
      MAX_DIRECTORIES = T.let(100, Integer)

      # Directories that hold vendored or generated YAML, never pipelines.
      IGNORED_DIRECTORIES = T.let(
        %w(
          .git .github .gitlab .idea .vs .vscode
          bin bower_components coverage dist node_modules obj out target vendor
        ).freeze,
        T::Array[String]
      )

      # Top-level keys that only a pipeline or a pipeline template declares.
      PIPELINE_KEYS = T.let(%w(steps jobs stages extends).freeze, T::Array[String])

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |filename| filename.match?(YAML_PATTERN) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain an Azure Pipelines YAML file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Azure Pipelines support is in beta. Set enable-beta-ecosystems to enable it."
          )
        end

        fetched_files = pipeline_files
        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          "No Azure Pipelines files found in #{directory}"
        )
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pipeline_files
        candidate_paths.filter_map { |path| pipeline_file(path) }
      end

      sig { params(path: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def pipeline_file(path)
        file = fetch_file_from_host(path)
        pipeline?(file.content) ? file : nil
      rescue Dependabot::DependencyFileNotFound
        nil
      end

      sig { params(content: T.nilable(String)).returns(T::Boolean) }
      def pipeline?(content)
        return false if content.nil? || content.strip.empty?

        parsed = YAML.safe_load(content, aliases: true, permitted_classes: [Date, Time])
        return false unless parsed.is_a?(Hash)

        PIPELINE_KEYS.any? { |key| parsed.key?(key) }
      rescue Psych::Exception
        # Azure Pipelines templates can contain constructs that are not valid YAML on
        # their own. They cannot be parsed for dependencies either, so skip them.
        false
      end

      sig { returns(T::Array[String]) }
      def candidate_paths
        @candidates = T.let([], T.nilable(T::Array[String]))
        @directories_visited = T.let(0, T.nilable(Integer))

        collect_yaml_paths(".", depth: 1)

        if budget_spent?
          Dependabot.logger.info(
            "Stopped looking for Azure Pipelines files in #{directory} after " \
            "#{directories_visited} directories and #{candidates.length} candidates"
          )
        end

        candidates
      end

      sig { params(dir: String, depth: Integer).void }
      def collect_yaml_paths(dir, depth:)
        return if budget_spent?

        @directories_visited = directories_visited + 1
        contents = repo_contents(dir: dir, raise_errors: false)

        contents.each do |entry|
          next unless entry.type == "file" && entry.name.match?(YAML_PATTERN)

          candidates << cleaned_path(dir, entry.name)
        end

        return if depth >= MAX_DEPTH

        contents.each do |entry|
          break if budget_spent?
          next unless entry.type == "dir" && !IGNORED_DIRECTORIES.include?(entry.name.downcase)

          collect_yaml_paths(cleaned_path(dir, entry.name), depth: depth + 1)
        end
      end

      sig { returns(T::Boolean) }
      def budget_spent?
        directories_visited >= MAX_DIRECTORIES || candidates.length >= MAX_CANDIDATES
      end

      sig { returns(T::Array[String]) }
      def candidates
        @candidates ||= T.let([], T.nilable(T::Array[String]))
      end

      sig { returns(Integer) }
      def directories_visited
        @directories_visited ||= T.let(0, T.nilable(Integer))
      end

      sig { params(dir: String, name: String).returns(String) }
      def cleaned_path(dir, name)
        File.join(dir, name).delete_prefix("./")
      end
    end
  end
end

Dependabot::FileFetchers.register("azure_pipelines", Dependabot::AzurePipelines::FileFetcher)
