# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/file_filtering"

module Dependabot
  module Prek
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      CONFIG_FILE_PATTERN = %r{(?:^|/)\.?prek\.toml$}i

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a prek.toml or .prek.toml file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(CONFIG_FILE_PATTERN) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << prek_config

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
      def prek_config
        @prek_config ||= T.let(
          fetch_file_from_host(config_file_name),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(String) }
      def config_file_name
        @config_file_name ||= T.let(
          repo_contents.find { |f| f.name.match?(CONFIG_FILE_PATTERN) }&.name ||
            "prek.toml",
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("prek", Dependabot::Prek::FileFetcher)
