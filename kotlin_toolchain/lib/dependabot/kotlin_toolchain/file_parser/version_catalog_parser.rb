# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/version"

module Dependabot
  module KotlinToolchain
    class FileParser < Dependabot::FileParsers::Base
      class VersionCatalogParser
        extend T::Sig

        LIBRARY_KEYS = %w(module group name version).freeze

        sig { params(file: Dependabot::DependencyFile, profile_name: String).void }
        def initialize(file:, profile_name:)
          @file = file
          @profile_name = profile_name
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies
          libraries = parsed["libraries"]
          return [] unless libraries.is_a?(Hash)

          library_declarations(libraries, prefix: []).filter_map do |alias_name, declaration|
            dependency_for(alias_name, declaration)
          end
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { returns(String) }
        attr_reader :profile_name

        sig { returns(T::Hash[String, Object]) }
        def parsed
          @parsed ||= T.let(
            TomlRB.parse(file.content.to_s),
            T.nilable(T::Hash[String, Object])
          )
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError => e
          raise Dependabot::DependencyFileNotParseable.new(file.name, "#{file.name}: #{e.message}")
        end

        # Gradle treats `.` in an alias like `-`, but TOML parses an unquoted
        # dotted key as nested tables, so `ktor.core = {...}` arrives here as
        # libraries["ktor"]["core"].
        sig do
          params(
            table: T::Hash[String, Object],
            prefix: T::Array[String]
          ).returns(T::Array[[String, Object]])
        end
        def library_declarations(table, prefix:)
          table.flat_map do |key, value|
            alias_parts = prefix + [key]
            if value.is_a?(Hash) && !value.keys.intersect?(LIBRARY_KEYS)
              library_declarations(value, prefix: alias_parts)
            else
              [[alias_parts.join("."), value]]
            end
          end
        end

        sig do
          params(
            alias_name: String,
            declaration: Object
          ).returns(T.nilable(Dependabot::Dependency))
        end
        def dependency_for(alias_name, declaration)
          details = declaration_details(declaration)
          return unless details

          version, metadata = version_and_metadata(alias_name, details)
          return unless version && metadata

          dependency_name = "#{details.fetch(:group)}:#{details.fetch(:artifact)}"
          Dependabot::Dependency.new(
            name: dependency_name,
            version: version,
            requirements: [{
              requirement: version,
              file: file.name,
              groups: ["dependencies"],
              source: nil,
              metadata: metadata
            }],
            package_manager: ECOSYSTEM,
            metadata: { profile: profile_name }
          )
        end

        sig { params(declaration: Object).returns(T.nilable(T::Hash[Symbol, Object])) }
        def declaration_details(declaration)
          if declaration.is_a?(String)
            parts = declaration.split(":")
            return unless parts.length >= 3

            return {
              group: parts[0],
              artifact: parts[1],
              version: parts[2],
              coordinate: parts.first(3).join(":"),
              format: "string"
            }
          end

          return unless declaration.is_a?(Hash)

          group, artifact = module_parts(declaration)
          return unless group && artifact

          {
            group: group,
            artifact: artifact,
            version: declaration["version"],
            coordinate: "#{group}:#{artifact}",
            format: "table"
          }
        end

        sig { params(declaration: T::Hash[String, Object]).returns([T.nilable(String), T.nilable(String)]) }
        def module_parts(declaration)
          module_value = declaration["module"]
          if module_value.is_a?(String)
            group, artifact = module_value.split(":", 2)
            return [group, artifact]
          end

          group = declaration["group"]
          artifact = declaration["name"]
          [
            group.is_a?(String) ? group : nil,
            artifact.is_a?(String) ? artifact : nil
          ]
        end

        sig do
          params(
            alias_name: String,
            details: T::Hash[Symbol, Object]
          ).returns([T.nilable(String), T.nilable(T::Hash[Symbol, Object])])
        end
        def version_and_metadata(alias_name, details)
          raw_version = details.fetch(:version)
          if raw_version.is_a?(String) && Version.correct?(raw_version)
            return [
              raw_version,
              {
                kind: "catalog_inline",
                alias: alias_name,
                value: raw_version,
                coordinate: details.fetch(:coordinate),
                format: details.fetch(:format),
                profile: profile_name
              }
            ]
          end

          return [nil, nil] unless raw_version.is_a?(Hash)

          reference = raw_version["ref"]
          return [nil, nil] unless reference.is_a?(String)

          version = referenced_version(reference)
          return [nil, nil] unless version

          [
            version,
            {
              kind: "catalog_version",
              alias: alias_name,
              version_key: reference,
              value: version,
              profile: profile_name
            }
          ]
        end

        sig { params(reference: String).returns(T.nilable(String)) }
        def referenced_version(reference)
          versions = parsed["versions"]
          return unless versions.is_a?(Hash)

          candidates = [versions[reference]]
          candidates << reference.split(".").reduce(T.let(versions, Object)) do |table, part|
            table.is_a?(Hash) ? table[part] : nil
          end
          candidates.find { |value| value.is_a?(String) && Version.correct?(value) }
        end
      end
    end
  end
end
