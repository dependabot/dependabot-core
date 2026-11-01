# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/apm/package_specifier"

module Dependabot
  module Apm
    # A parsed `apm.lock.yaml`, with its `dependencies` entries addressable by
    # APM's package identity (see PackageSpecifier#lockfile_key).
    class Lockfile
      extend T::Sig

      sig { params(file: Dependabot::DependencyFile).void }
      def initialize(file)
        @document = T.let(parse(file), T::Hash[Object, Object])
      end

      # The commit the lockfile pins for `key`, provided it was resolved from
      # `ref`. A lock entry resolved from a different ref is stale (APM
      # re-resolves it on the next run), so it is not reported as the
      # dependency's current commit.
      sig { params(key: String, ref: String).returns(T.nilable(String)) }
      def resolved_commit(key, ref:)
        entry = entry_for(key)
        return unless entry && entry["resolved_ref"] == ref

        commit = entry["resolved_commit"]
        commit.is_a?(String) && !commit.empty? ? commit : nil
      end

      # Moves the entry for `key` to `commit`. Its `content_hash` describes the
      # previous commit's contents, and APM fails a hash mismatch as a potential
      # supply-chain attack, so it is dropped for APM to recompute. The rest of
      # the entry (e.g. `deployed_files`) is kept.
      sig { params(key: String, commit: String).void }
      def pin_commit(key, commit)
        entry = entry_for(key)
        return unless entry

        entry["resolved_commit"] = commit
        entry.delete("content_hash")
      end

      sig { returns(String) }
      def to_yaml
        @document.to_yaml
      end

      private

      sig { params(key: String).returns(T.nilable(T::Hash[Object, Object])) }
      def entry_for(key)
        entries = @document["dependencies"]
        return unless entries.is_a?(Array)

        entries.each do |entry|
          return entry if entry.is_a?(Hash) && entry_key(entry) == key
        end
        nil
      end

      sig { params(entry: T::Hash[Object, Object]).returns(T.nilable(String)) }
      def entry_key(entry)
        repo_url = entry["repo_url"]
        return unless repo_url.is_a?(String)

        host = entry["host"]
        virtual_path = entry["virtual_path"]
        PackageSpecifier.lockfile_key(
          host: host.is_a?(String) && !host.empty? ? host : PackageSpecifier::DEFAULT_HOST,
          repo_url: repo_url,
          virtual_path: virtual_path.is_a?(String) && !virtual_path.empty? ? virtual_path : nil
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Hash[Object, Object]) }
      def parse(file)
        parsed = YAML.safe_load(T.must(file.content))
        parsed = {} if parsed.nil?
        raise Dependabot::DependencyFileNotParseable, file.path unless parsed.is_a?(Hash)

        parsed
      rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
        raise Dependabot::DependencyFileNotParseable, file.path
      end
    end
  end
end
