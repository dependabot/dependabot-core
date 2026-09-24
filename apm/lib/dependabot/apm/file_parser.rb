# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/apm/package_manager"
require "dependabot/apm/package_specifier"
require "dependabot/apm/version"

module Dependabot
  module Apm
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      MANIFEST_FILENAME = "apm.yml"
      LOCKFILE_FILENAME = "apm.lock.yaml"

      # The manifest dependency blocks we parse, mapped to the dependency groups
      # each block confers. `devDependencies` entries are marked non-production
      # via the "development" group.
      DEPENDENCY_BLOCKS = T.let(
        {
          "dependencies" => [].freeze,
          "devDependencies" => ["development"].freeze
        }.freeze,
        T::Hash[String, T::Array[String]]
      )

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        DEPENDENCY_BLOCKS.each do |block_key, groups|
          apm_entries_in(block_key).each do |entry|
            # v1 supports the string shorthand form (e.g. "owner/repo#v1.0.0").
            # Object entries (git:/registry:/id:/path:) and `mcp` entries are not
            # yet supported and are ignored.
            next unless entry.is_a?(String)

            spec = PackageSpecifier.parse(entry, default_host: default_host)
            next unless spec # local paths and unparseable specs are skipped

            dependency_set << build_dependency(spec, entry, groups)
          end
        end

        dependency_set.dependencies
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig do
        params(
          spec: Dependabot::Apm::PackageSpecifier,
          raw_entry: String,
          groups: T::Array[String]
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(spec, raw_entry, groups)
        ref = spec.ref
        version = Version.new(ref).to_s if ref && Version.correct?(ref)

        Dependency.new(
          name: spec.name,
          version: version,
          package_manager: "apm",
          requirements: [{
            requirement: nil,
            file: manifest_file.name,
            groups: groups,
            source: {
              type: "git",
              url: spec.git_url,
              ref: ref,
              branch: nil
            },
            metadata: { declaration_string: raw_entry }
          }]
        )
      end

      sig { params(block_key: String).returns(T::Array[T.untyped]) }
      def apm_entries_in(block_key)
        block = parsed_manifest[block_key]
        return [] unless block.is_a?(Hash)

        entries = block["apm"]
        entries.is_a?(Array) ? entries : []
      end

      sig { returns(String) }
      def default_host
        host = parsed_manifest["default_host"]
        host.is_a?(String) && !host.empty? ? host : PackageSpecifier::DEFAULT_HOST
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_manifest
        @parsed_manifest ||= T.let(
          begin
            parsed = YAML.safe_load(T.must(manifest_file.content), aliases: true)
            parsed = {} if parsed.nil?
            raise Dependabot::DependencyFileNotParseable, manifest_file.path unless parsed.is_a?(Hash)

            parsed
          rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
            raise Dependabot::DependencyFileNotParseable, manifest_file.path
          end,
          T.nilable(T::Hash[String, T.anything])
        )
      end

      sig { returns(Dependabot::DependencyFile) }
      def manifest_file
        @manifest_file ||= T.let(
          T.must(get_original_file(MANIFEST_FILENAME)),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          get_original_file(LOCKFILE_FILENAME),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { override.void }
      def check_required_files
        return if get_original_file(MANIFEST_FILENAME)

        raise "No #{MANIFEST_FILENAME}!"
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(apm_version),
          T.nilable(Dependabot::Apm::PackageManager)
        )
      end

      sig { returns(String) }
      def apm_version
        content = lockfile&.content
        version = content&.match(/^apm_version:\s*['"]?(?<version>[^'"\s]+)['"]?\s*$/)&.[](:version)
        version || DEFAULT_PACKAGE_MANAGER_VERSION
      end
    end
  end
end

Dependabot::FileParsers
  .register("apm", Dependabot::Apm::FileParser)
