# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/crystal_shards/package_manager"

module Dependabot
  module CrystalShards
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(MANIFEST_FILE)
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a #{MANIFEST_FILE}"
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Crystal Shards support is currently in beta. To enable it, add `enable_beta_ecosystems: true` to the " \
            "top-level of your `dependabot.yml`. See " \
            "https://docs.github.com/en/code-security/dependabot/working-with-dependabot" \
            "/dependabot-options-reference#enable-beta-ecosystems for details."
          )
        end

        fetched_files = T.let([], T::Array[DependencyFile])

        yml = shard_yml
        raise Dependabot::DependencyFileNotFound.new(nil, MANIFEST_FILE) unless yml

        fetched_files << yml
        lock = shard_lock
        fetched_files << lock if lock

        fetched_files
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def shard_yml
        @shard_yml ||= T.let(
          fetch_file_from_host(MANIFEST_FILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def shard_lock
        return @shard_lock if defined?(@shard_lock)

        @shard_lock = T.let(
          fetch_file_if_present(LOCKFILE),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("crystal_shards", Dependabot::CrystalShards::FileFetcher)
