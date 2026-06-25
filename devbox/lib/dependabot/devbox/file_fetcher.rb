# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Devbox
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_FILENAME = T.let("devbox.json", String)
      LOCKFILE_FILENAME = T.let("devbox.lock", String)

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a devbox.json."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(MANIFEST_FILENAME)
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # devbox is a beta ecosystem: only fetch when beta ecosystems are enabled.
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Devbox support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end

        fetched_files = [manifest_file]
        fetched_files << T.must(lockfile) if lockfile
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
            file = fetch_file_if_present(MANIFEST_FILENAME)
            raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message) unless file

            file
          end,
          T.nilable(DependencyFile)
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          fetch_file_if_present(LOCKFILE_FILENAME),
          T.nilable(DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("devbox", Dependabot::Devbox::FileFetcher)
