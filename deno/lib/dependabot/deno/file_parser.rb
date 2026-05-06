# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/deno/version"

module Dependabot
  module Deno
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      ECOSYSTEM = "deno"
      MANIFEST_FILENAMES = T.let(%w(deno.json deno.jsonc).freeze, T::Array[String])

      # Matches jsr:@scope/name[@constraint][/subpath] or npm:[@scope/]name[@constraint][/subpath]
      # Constraint and subpath are both optional per Deno's specifier format.
      JSR_SPECIFIER = %r{\Ajsr:(?<name>@[^@/]+/[^@/]+)(?:@(?<constraint>[^/]+))?(?:/[^\s]*)?\z}
      NPM_SPECIFIER = %r{\Anpm:(?<name>(?:@[^/]+/)?[^@/]+)(?:@(?<constraint>[^/]+))?(?:/[^\s]*)?\z}

      # Matches either a JSON string literal (with escapes), a line comment, a
      # block comment, or a trailing comma. The alternation lets gsub preserve
      # strings while stripping the JSONC-only constructs, so e.g. "//" inside a
      # URL value is not mistaken for the start of a comment.
      JSONC_TOKEN = %r{
        ("(?:\\.|[^"\\])*")    # JSON string literal
        | //[^\n]*             # line comment
        | /\*.*?\*/            # block comment
        | ,(?=\s*[\}\]])       # trailing comma
      }mx

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        # Multiple import aliases can reference the same underlying package
        # (e.g. "@std/path" and "@std/path/posix"). Keyed dedup by name +
        # source type collapses those without merging across registries — our
        # update checker only queries the first requirement's source, so
        # mixing jsr+npm under one Dependency would silently miss updates.
        # When the same name+source appears with different constraints, every
        # constraint is preserved as a separate requirement entry so callers
        # can update them all.
        deps_by_key = {}

        imports.each do |_alias_name, specifier|
          dep = parse_specifier(specifier.to_s)
          next unless dep

          key = [dep.name, dep.requirements.first[:source][:type]]
          existing = deps_by_key[key]
          deps_by_key[key] = if existing
                               Dependabot::Dependency.new(
                                 name: existing.name,
                                 version: existing.version,
                                 requirements: (existing.requirements + dep.requirements).uniq,
                                 package_manager: existing.package_manager
                               )
                             else
                               dep
                             end
        end

        deps_by_key.values.sort_by(&:name)
      end

      private

      sig { override.void }
      def check_required_files
        return if manifest_file

        raise "No deno.json or deno.jsonc found!"
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def imports
        parsed_manifest.fetch("imports", {})
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_manifest
        @parsed_manifest ||= T.let(
          parse_json_or_jsonc(T.must(manifest_file).content),
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def manifest_file
        @manifest_file ||= T.let(
          MANIFEST_FILENAMES.filter_map { |f| get_original_file(f) }.first,
          T.nilable(DependencyFile)
        )
      end

      sig { params(specifier: String).returns(T.nilable(Dependabot::Dependency)) }
      def parse_specifier(specifier)
        if (match = JSR_SPECIFIER.match(specifier))
          build_dependency(
            name: T.must(match[:name]),
            constraint: match[:constraint],
            source_type: "jsr"
          )
        elsif (match = NPM_SPECIFIER.match(specifier))
          build_dependency(
            name: T.must(match[:name]),
            constraint: match[:constraint],
            source_type: "npm"
          )
        end
      end

      sig { params(name: String, constraint: T.nilable(String), source_type: String).returns(Dependabot::Dependency) }
      def build_dependency(name:, constraint:, source_type:)
        version = constraint ? extract_version(constraint) : nil

        Dependabot::Dependency.new(
          name: name,
          version: version,
          requirements: [{
            requirement: constraint,
            file: T.must(manifest_file).name,
            groups: ["imports"],
            source: { type: source_type }
          }],
          package_manager: ECOSYSTEM
        )
      end

      sig { params(constraint: String).returns(T.nilable(String)) }
      def extract_version(constraint)
        version_str = constraint.sub(/\A[~^>=<!\s]+/, "")
        return version_str if Deno::Version.correct?(version_str)

        nil
      end

      sig { params(content: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
      def parse_json_or_jsonc(content)
        return {} unless content

        cleaned = content.gsub(JSONC_TOKEN) { ::Regexp.last_match(1) || "" }

        JSON.parse(cleaned)
      end
    end
  end
end

Dependabot::FileParsers.register("deno", Dependabot::Deno::FileParser)
