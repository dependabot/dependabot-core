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

      # Shown when file fetching runs with beta ecosystems disabled. apm is a
      # beta ecosystem, so it only operates when a repo opts in; surfacing the
      # remediation here avoids the misleading "apm.yml not found" message when
      # the manifest actually exists and the real blocker is the disabled flag.
      BETA_DISABLED_MESSAGE =
        "apm is a beta ecosystem. Set `enable-beta-ecosystems: true` in your " \
        "dependabot.yml so Dependabot fetches and updates #{MANIFEST_FILENAME}.".freeze

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
        # beta-ecosystems feature flag (see NEW_ECOSYSTEMS.md). When the flag is
        # off, tell the user to enable it rather than claim the manifest is
        # missing, which would hide the real remediation when apm.yml exists.
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            File.join(directory, MANIFEST_FILENAME),
            BETA_DISABLED_MESSAGE
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

        @lockfile = T.let(
          fetch_file_if_present(LOCKFILE_FILENAME)&.tap { |f| f.support_file = true },
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
