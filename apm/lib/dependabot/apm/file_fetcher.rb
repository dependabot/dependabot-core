# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Apm
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      MANIFEST_FILENAME = "apm.yml"
      LOCKFILE_FILENAME = "apm.lock.yaml"

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(MANIFEST_FILENAME)
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain an #{MANIFEST_FILENAME} file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # apm is a beta ecosystem, so file fetching is hidden behind the
        # beta-ecosystems feature flag (see NEW_ECOSYSTEMS.md).
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            File.join(directory, MANIFEST_FILENAME),
            self.class.required_files_message
          )
        end

        fetched_files = T.let([manifest_file], T::Array[DependencyFile])
        fetched_files << T.must(lockfile) if lockfile
        fetched_files
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.anything])) }
      def ecosystem_versions
        return unless lockfile

        version = parsed_lockfile_apm_version
        return unless version

        { package_managers: { "apm" => version } }
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def manifest_file
        @manifest_file ||= T.let(
          fetch_file_from_host(MANIFEST_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        return @lockfile if defined?(@lockfile)

        # Fetched as a regular (non-support) file: when a ref bump changes it the
        # file updater rewrites it, and support files are dropped from a PR when
        # any non-support file also changes, which would leave it stale.
        @lockfile = T.let(
          fetch_file_if_present(LOCKFILE_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(String)) }
      def parsed_lockfile_apm_version
        content = lockfile&.content
        return unless content

        match = content.match(/^apm_version:\s*['"]?(?<version>[^'"\s]+)['"]?\s*$/)
        match && match[:version]
      end
    end
  end
end

Dependabot::FileFetchers
  .register("apm", Dependabot::Apm::FileFetcher)
