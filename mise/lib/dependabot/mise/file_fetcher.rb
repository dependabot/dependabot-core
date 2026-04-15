# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Mise
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a mise configuration file " \
          "(mise.toml, .mise.toml, mise.<env>.toml, or .mise.<env>.toml)."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |filename| mise_config_file?(filename) }
      end

      sig { params(filename: String).returns(T::Boolean) }
      def self.mise_config_file?(filename)
        filename == "mise.toml" ||
          filename == ".mise.toml" ||
          filename.match?(/^mise\.[a-zA-Z0-9_-]+\.toml$/) || # mise.<env>.toml
          filename.match?(/^\.mise\.[a-zA-Z0-9_-]+\.toml$/) # .mise.<env>.toml
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # Implement beta feature flag check
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Mise support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        # Fetch all mise config files that exist in the repo
        fetched_files = repo_contents.filter_map do |file|
          # Access properties directly - repo_contents items have name and type
          next unless file.type == "file"
          next unless self.class.mise_config_file?(file.name)

          fetch_file_from_host(file.name)
        end

        return fetched_files unless fetched_files.empty?

        raise Dependabot::DependencyFileNotFound.new(
          "mise.toml",
          "No mise configuration file found"
        )
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("mise", Dependabot::Mise::FileFetcher)
