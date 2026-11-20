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

      URI_KIND = "uri"
      PROJECT_SCOPE = "project"
      TARGET_NAME_REGEX = /\A[a-z][a-z0-9-]*\z/

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

      # The targets the lockfile records project files as deployed to, from its
      # `deployments` entries. MCP and LSP servers are `uri` entries whose
      # target (`mcp`, `lsp`) isn't a harness, so they are skipped. Not every
      # name is a harness either (APM records unattributed paths as `legacy`),
      # so callers check these against `apm targets`. A lockfile without
      # `deployments` yields none: like APM, this doesn't infer harnesses from
      # legacy `deployed_files` paths.
      sig { returns(T::Array[String]) }
      def deployment_targets
        project_deployments.filter_map do |deployment|
          deployment_name(deployment, "target") unless deployment["kind"] == URI_KIND
        end.uniq.sort
      end

      # The runtimes (e.g. `claude`, `intellij`) the lockfile records MCP and
      # LSP servers as configured for.
      sig { returns(T::Array[String]) }
      def service_runtimes
        project_deployments.filter_map do |deployment|
          deployment_name(deployment, "runtime") if deployment["kind"] == URI_KIND
        end.uniq.sort
      end

      # The digest (e.g. `sha256:…`) the lockfile records for each file a
      # dependency deployed, keyed by the file's path.
      sig { returns(T::Hash[String, String]) }
      def deployed_file_hashes
        entries = @document["dependencies"]
        return {} unless entries.is_a?(Array)

        entries.each_with_object({}) do |entry, hashes|
          recorded = entry["deployed_file_hashes"] if entry.is_a?(Hash)
          next unless recorded.is_a?(Hash)

          recorded.each { |path, digest| hashes[path] = digest if path.is_a?(String) && digest.is_a?(String) }
        end
      end

      # Every path the lockfile records a dependency as deploying to the
      # project: its `deployed_files` (files and the directories that hold
      # them), its `deployed_file_hashes` and the project-scope `deployments`.
      # MCP and LSP servers are `uri` deployments named by server, not path,
      # so they are skipped.
      sig { returns(T::Array[String]) }
      def deployed_paths
        paths = deployed_file_hashes.keys
        entries = @document["dependencies"]
        if entries.is_a?(Array)
          entries.each do |entry|
            files = entry["deployed_files"] if entry.is_a?(Hash)
            paths.concat(files.grep(String)) if files.is_a?(Array)
          end
        end
        project_deployments.each do |deployment|
          value = deployment["value"]
          paths << value if value.is_a?(String) && deployment["kind"] != URI_KIND
        end
        paths.uniq
      end

      sig { returns(String) }
      def to_yaml
        @document.to_yaml
      end

      private

      sig { returns(T::Array[T::Hash[Object, Object]]) }
      def project_deployments
        deployments = @document["deployments"]
        return [] unless deployments.is_a?(Array)

        deployments.select { |deployment| deployment.is_a?(Hash) && deployment["scope"] == PROJECT_SCOPE }
      end

      sig { params(deployment: T::Hash[Object, Object], field: String).returns(T.nilable(String)) }
      def deployment_name(deployment, field)
        name = deployment[field]
        name if name.is_a?(String) && name.match?(TARGET_NAME_REGEX)
      end

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
