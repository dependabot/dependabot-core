# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module GoModules
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("go.mod")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a go.mod."
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def ecosystem_versions
        {
          package_managers: {
            "gomod" => go_mod.content&.match(/^go\s(\d+\.\d+)/)&.captures&.first || "unknown"
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # Ensure we always check out the full repo contents for go_module
        # updates.
        SharedHelpers.in_a_temporary_repo_directory(
          directory,
          clone_repo_contents
        ) do
          fetched_files = [go_mod]
          # Fetch the (optional) go.sum
          fetched_files << T.must(go_sum) if go_sum
          fetched_files
        end
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def go_mod
        @go_mod ||= T.let(T.must(fetch_file_if_present("go.mod")), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_sum
        @go_sum ||= T.let(fetch_file_if_present("go.sum"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileFetchers
  .register("go_modules", Dependabot::GoModules::FileFetcher)
