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
        # Reading the host first also validates the manifest and raises
        # DependencyFileNotParseable before we walk it for source positions.
        host = default_host

        DEPENDENCY_BLOCKS.each do |block_key, groups|
          apm_entries_in(block_key).each do |entry, declaration_line|
            # v1 supports the string shorthand form (e.g. "owner/repo#v1.0.0").
            # Object entries (git:/registry:/id:/path:) and `mcp` entries are
            # not yet supported and are skipped by only reading scalar entries.
            spec = PackageSpecifier.parse(entry, default_host: host)
            next unless spec # local paths and unparseable specs are skipped

            # Only entries pinned to a semver tag are updatable. Branch-, SHA-
            # and unpinned entries are resolved by APM's own lockfile, so we
            # leave them out of the dependency set entirely rather than have the
            # update checker reach out to the git remote for something we will
            # never bump.
            ref = spec.ref
            next unless ref && Version.correct?(ref)

            dependency_set << build_dependency(spec, entry, declaration_line, groups)
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
          declaration_line: Integer,
          groups: T::Array[String]
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(spec, raw_entry, declaration_line, groups)
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
            # `declaration_line` (0-based) pins the exact manifest line the
            # entry came from, so the file updater rewrites only that
            # occurrence and never an identical string elsewhere.
            metadata: {
              declaration_string: raw_entry,
              declaration_line: declaration_line.to_s
            }
          }]
        )
      end

      # Returns each `<block>.apm` entry as a [value, 0-based source line] pair.
      # Only scalar entries are returned, so object-form entries (git:/registry:
      # /id:/path: maps) are naturally skipped.
      sig { params(block_key: String).returns(T::Array[[String, Integer]]) }
      def apm_entries_in(block_key)
        block = ast_mapping_value(manifest_ast, block_key)
        return [] unless block.is_a?(Psych::Nodes::Mapping)

        sequence = ast_mapping_value(block, "apm")
        return [] unless sequence.is_a?(Psych::Nodes::Sequence)

        sequence.children.filter_map do |node|
          next unless node.is_a?(Psych::Nodes::Scalar)

          [node.value, node.start_line]
        end
      end

      # Looks up the value node for `key` in a YAML mapping AST node, whose
      # children alternate [key, value, key, value, ...].
      sig do
        params(mapping: T.nilable(Psych::Nodes::Node), key: String)
          .returns(T.nilable(Psych::Nodes::Node))
      end
      def ast_mapping_value(mapping, key)
        return unless mapping.is_a?(Psych::Nodes::Mapping)

        children = mapping.children
        index = 0
        while index < children.length
          node_key = children[index]
          return children[index + 1] if node_key.is_a?(Psych::Nodes::Scalar) && node_key.value == key

          index += 2
        end
        nil
      end

      sig { returns(T.nilable(Psych::Nodes::Mapping)) }
      def manifest_ast
        return @manifest_ast if defined?(@manifest_ast)

        document = YAML.parse(T.must(manifest_file.content))
        root = document.is_a?(Psych::Nodes::Document) ? document.root : nil
        @manifest_ast = T.let(
          root.is_a?(Psych::Nodes::Mapping) ? root : nil,
          T.nilable(Psych::Nodes::Mapping)
        )
      end

      sig { returns(String) }
      def default_host
        host = parsed_manifest["default_host"]
        host.is_a?(String) && !host.empty? ? host : PackageSpecifier::DEFAULT_HOST
      end

      sig { returns(T::Hash[String, Object]) }
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
          T.nilable(T::Hash[String, Object])
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
