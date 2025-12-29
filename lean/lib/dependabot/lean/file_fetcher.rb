# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/lean"

module Dependabot
  module Lean
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        basenames = filenames.map { |f| File.basename(f) }
        basenames.include?(LEAN_TOOLCHAIN_FILENAME) || basenames.include?(LAKE_MANIFEST_FILENAME)
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a #{LEAN_TOOLCHAIN_FILENAME} or #{LAKE_MANIFEST_FILENAME} file"
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = []

        # Fetch toolchain file (Lean version)
        toolchain_file = lean_toolchain_file
        fetched_files << toolchain_file if toolchain_file

        # Fetch Lake manifest (lockfile for dependencies)
        manifest_file = lake_manifest_file
        fetched_files << manifest_file if manifest_file

        # Fetch lakefile for context (optional)
        lakefile = lakefile_toml || lakefile_lean
        fetched_files << lakefile if lakefile

        return fetched_files unless fetched_files.empty?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          self.class.required_files_message
        )
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lean_toolchain_file
        fetch_file_if_present(LEAN_TOOLCHAIN_FILENAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lake_manifest_file
        fetch_file_if_present(LAKE_MANIFEST_FILENAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lakefile_toml
        fetch_file_if_present(LAKEFILE_TOML_FILENAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lakefile_lean
        fetch_file_if_present(LAKEFILE_LEAN_FILENAME)
      end
    end
  end
end

Dependabot::FileFetchers.register("lean", Dependabot::Lean::FileFetcher)
