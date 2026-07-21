# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/deno/helpers"
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
        # Multiple import aliases can reference the same underlying package
        # (e.g. "@std/path" and "@std/path/posix"). Keyed dedup by name +
        # source type collapses those without merging across registries — our
        # update checker only queries the first requirement's source, so
        # mixing jsr+npm under one Dependency would silently miss updates.
        # When the same name+source appears with different constraints, every
        # constraint is preserved as a separate requirement entry so callers
        # can update them all.
        deps_by_key = {}

        manifest_files.each do |file|
          imports_for(file).each do |_alias_name, specifier|
            dep = parse_specifier(specifier.to_s, file)
            next unless dep

            source_type = dependency_source_type(T.must(dep.requirements.first))
            key = [dep.name, source_type]
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
        end

        deps_by_key.values.sort_by(&:name)
      end

      private

      sig { params(requirement: Dependabot::DependencyRequirement).returns(String) }
      def dependency_source_type(requirement)
        value = requirement.source_string(:type)
        raise TypeError, "Expected dependency source type to be a String" unless value.is_a?(String)

        value
      end

      sig { override.void }
      def check_required_files
        return if manifest_files.any?

        raise "No deno.json or deno.jsonc found!"
      end

      # The root manifest plus every workspace member manifest. Members are
      # fetched relative to the root (e.g. "packages/foo/deno.json"), so match
      # on basename rather than the full path.
      sig { returns(T::Array[DependencyFile]) }
      def manifest_files
        @manifest_files ||= T.let(
          dependency_files.select { |f| MANIFEST_FILENAMES.include?(File.basename(f.name)) },
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(file: DependencyFile).returns(T::Hash[String, String]) }
      def imports_for(file)
        T.cast(Helpers.parse_json_or_jsonc(file.content).fetch("imports", {}), T::Hash[String, String])
      end

      sig { params(specifier: String, file: DependencyFile).returns(T.nilable(Dependabot::Dependency)) }
      def parse_specifier(specifier, file)
        if (match = JSR_SPECIFIER.match(specifier))
          build_dependency(
            name: T.must(match[:name]),
            constraint: match[:constraint],
            source_type: "jsr",
            file: file
          )
        elsif (match = NPM_SPECIFIER.match(specifier))
          build_dependency(
            name: T.must(match[:name]),
            constraint: match[:constraint],
            source_type: "npm",
            file: file
          )
        end
      end

      sig do
        params(
          name: String,
          constraint: T.nilable(String),
          source_type: String,
          file: DependencyFile
        ).returns(Dependabot::Dependency)
      end
      def build_dependency(name:, constraint:, source_type:, file:)
        version = constraint ? extract_version(constraint) : nil

        Dependabot::Dependency.new(
          name: name,
          version: version,
          requirements: [{
            requirement: constraint,
            file: file.name,
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
    end
  end
end

Dependabot::FileParsers.register("deno", Dependabot::Deno::FileParser)
