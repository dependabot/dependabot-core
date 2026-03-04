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

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependencies = []

        imports.each do |_alias_name, specifier|
          dep = parse_specifier(specifier.to_s)
          dependencies << dep if dep
        end

        dependencies.sort_by(&:name)
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

        # Strip single-line comments and trailing commas for JSONC support
        cleaned = content
                  .gsub(%r{//[^\n]*}, "")
                  .gsub(%r{/\*.*?\*/}m, "")
                  .gsub(/,\s*([}\]])/, '\1')

        JSON.parse(cleaned)
      end
    end
  end
end

Dependabot::FileParsers.register("deno", Dependabot::Deno::FileParser)
