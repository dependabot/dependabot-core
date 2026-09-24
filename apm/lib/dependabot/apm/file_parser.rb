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

      # Block scalars (folded `>` / literal `|`) are skipped outright: multi-line
      # folding and chomping mean their decoded value need not be a contiguous
      # substring of the raw source span, so the updater could not rewrite them
      # and the job would fail with "Expected content to change!". Flow scalars
      # are additionally verified with `scalar_round_trips?`, which also excludes
      # escaped quoted scalars whose decoding differs from their source bytes.
      BLOCK_SCALAR_STYLES = T.let(
        [Psych::Nodes::Scalar::LITERAL, Psych::Nodes::Scalar::FOLDED].freeze,
        T::Array[Integer]
      )

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        # Non-GitHub git hosts (e.g. GitLab) are case-sensitive, so use a
        # case-sensitive dependency set to keep repositories that differ only by
        # case distinct. PackageSpecifier canonicalises GitHub owner/repo casing
        # itself, so case-insensitive GitHub paths still deduplicate correctly.
        dependency_set = DependencySet.new(case_sensitive: true)
        # Reading the host first also validates the manifest and raises
        # DependencyFileNotParseable before we walk it for source positions.
        host = default_host

        # When the manifest configures a default registry, APM routes plain
        # string-shorthand entries through that registry rather than Git. We
        # cannot resolve registry versions (registry dependencies are out of
        # scope for v1), so those entries are skipped rather than bumped against
        # a git remote they may not even belong to. Explicit clone URLs are
        # never registry-routed and are still updated.
        skip_shorthand = default_registry_configured?

        DEPENDENCY_BLOCKS.each do |block_key, groups|
          apm_entries_in(block_key).each do |entry, declaration_span|
            # v1 supports the string shorthand form (e.g. "owner/repo#v1.0.0").
            # Object entries (git:/registry:/id:/path:) and `mcp` entries are
            # not yet supported and are skipped by only reading scalar entries.
            spec = PackageSpecifier.parse(entry, default_host: host)
            next unless spec # local paths and unparseable specs are skipped
            next if skip_shorthand && PackageSpecifier.shorthand?(entry)

            # Only entries pinned to a semver tag are updatable. Branch-, SHA-
            # and unpinned entries are resolved by APM's own lockfile, so we
            # leave them out of the dependency set entirely rather than have the
            # update checker reach out to the git remote for something we will
            # never bump.
            ref = spec.ref
            next unless ref && Version.correct?(ref)

            dependency_set << build_dependency(spec, entry, declaration_span, groups)
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
          declaration_span: String,
          groups: T::Array[String]
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(spec, raw_entry, declaration_span, groups)
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
            # `declaration_span` locates the exact manifest scalar (see
            # `encode_span`) so the file updater rewrites only that occurrence,
            # never an identical string elsewhere in the file.
            metadata: {
              declaration_string: raw_entry,
              declaration_span: declaration_span
            }
          }]
        )
      end

      # Returns each `<block>.apm` entry as a [value, encoded source span] pair.
      # Only round-tripping flow scalar entries are returned: object-form entries
      # (git:/registry:/id:/path: maps), block scalars (folded/literal) and
      # escaped scalars whose decoding differs from their source bytes are all
      # skipped, since the updater can only rewrite a value it finds verbatim in
      # the source span.
      sig { params(block_key: String).returns(T::Array[[String, String]]) }
      def apm_entries_in(block_key)
        block = ast_mapping_value(manifest_ast, block_key)
        return [] unless block.is_a?(Psych::Nodes::Mapping)

        sequence = ast_mapping_value(block, "apm")
        return [] unless sequence.is_a?(Psych::Nodes::Sequence)

        sequence.children.filter_map do |node|
          next unless node.is_a?(Psych::Nodes::Scalar)
          next if BLOCK_SCALAR_STYLES.include?(node.style)
          next unless scalar_round_trips?(node)

          [node.value, encode_span(node)]
        end
      end

      # Encodes a scalar node's exact source span as
      # "start_line:start_column:end_line:end_column" (all 0-based). The span
      # brackets the whole token, including any surrounding quotes, which lets
      # the updater rewrite block and flow sequences alike.
      sig { params(node: Psych::Nodes::Scalar).returns(String) }
      def encode_span(node)
        [node.start_line, node.start_column, node.end_line, node.end_column].join(":")
      end

      # True when the scalar's decoded value appears verbatim inside its raw
      # source span. The updater rewrites a ref by locating the declaration
      # string (the decoded `node.value`) inside that span slice, so a scalar
      # whose decoding differs from its source bytes -- e.g. a double-quoted
      # scalar using escapes such as `\/` or `\x23` -- can never be rewritten and
      # would fail the job with "Expected content to change!". Skipping those
      # entries here mirrors the updater's own `original.include?(declaration)`
      # guard, and the offset maths matches `FileUpdater#span_offsets` so an
      # entry that survives parsing is always rewritable.
      sig { params(node: Psych::Nodes::Scalar).returns(T::Boolean) }
      def scalar_round_trips?(node)
        content = T.must(manifest_file.content)
        lines = content.each_line.to_a
        start_offset = lines.first(node.start_line).sum(&:length) + node.start_column
        end_offset = lines.first(node.end_line).sum(&:length) + node.end_column
        return false if start_offset >= end_offset || end_offset > content.length

        T.must(content[start_offset...end_offset]).include?(node.value)
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

      # APM routes string-shorthand dependencies through a configured default
      # registry instead of Git. Only the project-level `registries.default`
      # selector (a string naming a configured entry) is visible here; a user's
      # `~/.apm/config.json` default is not part of the repository, so this
      # guards the case that is reproducible from the manifest alone.
      sig { returns(T::Boolean) }
      def default_registry_configured?
        registries = parsed_manifest["registries"]
        return false unless registries.is_a?(Hash)

        default = registries["default"]
        return false unless default.is_a?(String)

        !default.empty?
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
