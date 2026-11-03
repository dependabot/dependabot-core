# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Nimble
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_SUFFIX = ".nimble"

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Nimble package file (a `<name>.nimble` file)."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| name.end_with?(MANIFEST_SUFFIX) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Nimble support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        manifests = repo_contents(raise_errors: false)
                    .select { |file| file.type == "file" && file.name.end_with?(MANIFEST_SUFFIX) }
                    .map { |file| fetch_file_from_host(file.name) }
        return manifests if manifests.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.anything])) }
      def ecosystem_versions
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("nimble", Dependabot::Nimble::FileFetcher)
