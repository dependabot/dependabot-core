# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a TODO manifest file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        # TODO: Implement logic to check if required files are present
        # Example: filenames.any? { |name| name == "manifest.json" }
        false
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # Implement beta feature flag check
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Bazel is currently in beta. Please contact Dependabot support to enable it."
          )
        end

        fetched_files = []

        # TODO: Implement file fetching logic
        # Example:
        # fetched_files << fetch_file_from_host("manifest.json")

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        # TODO: Return supported ecosystem versions
        # Example: { package_managers: { "bazel" => "1.0.0" } }
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("bazel", Dependabot::Bazel::FileFetcher)
