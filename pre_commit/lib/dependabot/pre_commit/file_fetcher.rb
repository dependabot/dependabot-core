# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/file_filtering"

module Dependabot
  module PreCommit
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      CONFIG_FILE_PATTERN = /\.pre-commit(-config)?\.ya?ml$/i

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a .pre-commit-config.yaml, .pre-commit-config.yml, " \
          ".pre-commit.yaml, or .pre-commit.yml file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(CONFIG_FILE_PATTERN) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # unless allow_beta_ecosystems?
        #   raise Dependabot::DependencyFileNotFound.new(
        #     nil,
        #     "PreCommit support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
        #   )
        # end

        fetched_files = []
        fetched_files << pre_commit_config

        fetched_files.reject do |file|
          Dependabot::FileFiltering.should_exclude_path?(file.name, "file from final collection", @exclude_paths)
        end
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        nil
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def pre_commit_config
        @pre_commit_config ||= T.let(
          fetch_file_from_host(config_file_name),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(String) }
      def config_file_name
        @config_file_name ||= T.let(
          repo_contents.find { |f| f.name.match?(CONFIG_FILE_PATTERN) }&.name ||
            ".pre-commit-config.yaml",
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("pre_commit", Dependabot::PreCommit::FileFetcher)
