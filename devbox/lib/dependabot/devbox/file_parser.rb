# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/devbox/helpers"
require "dependabot/devbox/version"

module Dependabot
  module Devbox
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      ECOSYSTEM = T.let("devbox", String)
      MANIFEST_FILENAME = T.let("devbox.json", String)
      LOCKFILE_FILENAME = T.let("devbox.lock", String)
      # An entry without an "@constraint" suffix tracks the newest release.
      DEFAULT_CONSTRAINT = T.let("latest", String)
      SOURCE_TYPE = T.let("nixhub", String)

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        package_entries.filter_map do |entry|
          next unless entry.is_a?(String)

          name, constraint = split_package_entry(entry)
          next if name.empty?

          Dependabot::Dependency.new(
            name: name,
            version: resolved_versions[entry],
            requirements: [{
              requirement: constraint,
              file: MANIFEST_FILENAME,
              groups: [],
              source: { type: SOURCE_TYPE }
            }],
            package_manager: ECOSYSTEM
          )
        end.sort_by(&:name)
      end

      private

      sig { override.void }
      def check_required_files
        return if manifest

        raise "No devbox.json found!"
      end

      sig { returns(T.nilable(DependencyFile)) }
      def manifest
        @manifest ||= T.let(
          dependency_files.find { |f| File.basename(f.name) == MANIFEST_FILENAME },
          T.nilable(DependencyFile)
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          dependency_files.find { |f| File.basename(f.name) == LOCKFILE_FILENAME },
          T.nilable(DependencyFile)
        )
      end

      # The "packages" field in devbox.json is an array of `name@constraint`
      # strings — the only form supported in beta. Any other shape (e.g. the
      # object form) yields no dependencies.
      sig { returns(Array) }
      def package_entries
        packages = Helpers.parse_json_or_jsonc(manifest&.content).fetch("packages", [])
        packages.is_a?(Array) ? packages : []
      end

      # Splits a package entry on the LAST "@" so future scoped names
      # (e.g. "@org/pkg@1.0") resolve correctly. An entry with no constraint
      # (or a leading-"@" scoped name with none) defaults to "latest".
      sig { params(entry: String).returns([String, String]) }
      def split_package_entry(entry)
        index = entry.rindex("@")
        return [entry, DEFAULT_CONSTRAINT] if index.nil? || index.zero?

        [T.must(entry[0...index]), T.must(entry[(index + 1)..])]
      end

      # Maps each manifest package entry (the full `name@constraint` string) to
      # the resolved version recorded in devbox.lock. devbox.lock is strict JSON.
      sig { returns(T::Hash[String, String]) }
      def resolved_versions
        @resolved_versions ||= T.let(parse_lockfile_versions, T.nilable(T::Hash[String, String]))
      end

      sig { returns(T::Hash[String, String]) }
      def parse_lockfile_versions
        content = lockfile&.content
        return {} unless content

        parsed = JSON.parse(content)
        packages = parsed.is_a?(Hash) ? parsed.fetch("packages", {}) : {}
        return {} unless packages.is_a?(Hash)

        packages.each_with_object({}) do |(entry, data), versions|
          version = data.is_a?(Hash) ? data["version"] : nil
          versions[entry] = version if version.is_a?(String)
        end
      rescue JSON::ParserError
        {}
      end
    end
  end
end

Dependabot::FileParsers.register("devbox", Dependabot::Devbox::FileParser)
