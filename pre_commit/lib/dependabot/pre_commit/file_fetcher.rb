# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/file_filtering"

module Dependabot
  module PreCommit
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      # Matches pre-commit's YAML configs (.pre-commit-config.yaml et al.) as
      # well as prek's TOML config (prek.toml / .prek.toml), which is
      # configuration-compatible once parsed.
      CONFIG_FILE_PATTERN = %r{\.pre-commit(-config)?\.ya?ml$|(?:^|/)\.?prek\.toml$}i

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a .pre-commit-config.yaml, .pre-commit-config.yml, " \
          ".pre-commit.yaml, .pre-commit.yml, prek.toml, or .prek.toml file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(CONFIG_FILE_PATTERN) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        config_files.reject do |file|
          Dependabot::FileFiltering.should_exclude_path?(file.name, "file from final collection", @exclude_paths)
        end
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        nil
      end

      private

      # Fetches every config file present in the repo (a repo may use both a
      # YAML pre-commit config and a TOML prek config). Falls back to the
      # default YAML name so a missing-file error is raised if none are found.
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def config_files
        @config_files ||= T.let(
          config_file_names.map { |name| fetch_file_from_host(name) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[String]) }
      def config_file_names
        names = repo_contents.select { |f| f.name.match?(CONFIG_FILE_PATTERN) }.map(&:name)
        names.empty? ? [".pre-commit-config.yaml"] : names
      end
    end
  end
end

Dependabot::FileFetchers.register("pre_commit", Dependabot::PreCommit::FileFetcher)
