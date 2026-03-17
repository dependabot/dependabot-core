# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Mise
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_FILE = T.let("mise.toml", String)

      # NOTE: mise also supports .mise.toml, .config/mise.toml, and mise/config.toml
      # as alternative config file locations. These are not currently supported.

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a mise.toml file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(MANIFEST_FILE)
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

        [fetch_file_from_host(MANIFEST_FILE)]
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("mise", Dependabot::Mise::FileFetcher)
