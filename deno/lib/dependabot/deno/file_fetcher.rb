# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Deno
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_FILENAMES = T.let(%w(deno.json deno.jsonc).freeze, T::Array[String])

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a deno.json or deno.jsonc."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| MANIFEST_FILENAMES.include?(f) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Deno ecosystem support is in beta. Set enable-beta-ecosystems to use it."
          )
        end

        fetched_files = []
        fetched_files << manifest_file
        fetched_files << lockfile if lockfile
        fetched_files
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        nil
      end

      private

      sig { returns(DependencyFile) }
      def manifest_file
        @manifest_file ||= T.let(
          begin
            file = MANIFEST_FILENAMES.filter_map { |f| fetch_file_if_present(f) }.first
            raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message) unless file

            file
          end,
          T.nilable(DependencyFile)
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          fetch_file_if_present("deno.lock"),
          T.nilable(DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("deno", Dependabot::Deno::FileFetcher)
