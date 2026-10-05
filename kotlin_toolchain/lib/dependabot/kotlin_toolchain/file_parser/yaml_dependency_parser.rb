# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base"
require "dependabot/kotlin_toolchain/compatibility_profile"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/version"
require "dependabot/kotlin_toolchain/yaml_parser"

module Dependabot
  module KotlinToolchain
    class FileParser < Dependabot::FileParsers::Base
      class YamlDependencyParser
        extend T::Sig

        SETTINGS_KEY = /\A(?:test-)?settings(?:@.+)?\z/
        DEPENDENCIES_KEY = /\A(?:test-)?dependencies(?:@.+)?\z/

        sig do
          params(
            file: Dependabot::DependencyFile,
            profile: CompatibilityProfile
          ).void
        end
        def initialize(file:, profile:)
          @file = file
          @profile = profile
          @parsed = T.let(nil, T.nilable(T::Hash[String, Object]))
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies
          result = T.let([], T::Array[Dependabot::Dependency])

          parsed.each do |key, value|
            if key.match?(DEPENDENCIES_KEY) && value.is_a?(Array)
              result.concat(
                dependencies_from_list(
                  value,
                  path: [key],
                  groups: key.start_with?("test-") ? ["test"] : ["dependencies"]
                )
              )
            end

            next unless key.match?(SETTINGS_KEY) && value.is_a?(Hash)

            groups = key.start_with?("test-") ? ["test"] : ["dependencies"]
            result.concat(built_in_dependencies(value, root_path: [key], groups: groups))
            result.concat(processor_dependencies(value, root_path: [key], groups: groups))
            result.concat(compiler_plugin_dependencies(value, root_path: [key], groups: groups))
          end

          result.concat(project_maven_plugins)
          result.concat(maven_plugin_extra_dependencies)
          result
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { returns(CompatibilityProfile) }
        attr_reader :profile

        sig { returns(T::Hash[String, Object]) }
        def parsed
          @parsed ||= begin
            value = YamlParser.load(file.content.to_s, filename: file.name)
            value.is_a?(Hash) ? value : {}
          end
        end

        sig do
          params(
            settings: T::Hash[String, Object],
            root_path: T::Array[T.any(String, Integer)],
            groups: T::Array[String]
          ).returns(T::Array[Dependabot::Dependency])
        end
        def built_in_dependencies(settings, root_path:, groups:)
          profile.built_ins.filter_map do |definition|
            path = T.cast(definition.fetch(:path), T::Array[String])
            value = dig_value(settings, path)
            next unless value.is_a?(String) && Version.correct?(value)

            dependency_from(
              name: T.cast(definition.fetch(:dependency), String),
              version: value,
              groups: groups,
              source: source_for(definition),
              metadata: {
                kind: "yaml_value",
                path: root_path + path,
                value: value,
                version_source: "settings",
                setting_path: (root_path + path).join("."),
                profile: profile.name
              }
            )
          end
        end

        sig do
          params(
            settings: T::Hash[String, Object],
            root_path: T::Array[T.any(String, Integer)],
            groups: T::Array[String]
          ).returns(T::Array[Dependabot::Dependency])
        end
        def processor_dependencies(settings, root_path:, groups:)
          paths = [
            %w(java annotationProcessing processors),
            %w(kotlin ksp processors)
          ]

          paths.flat_map do |path|
            value = dig_value(settings, path)
            next [] unless value.is_a?(Array)

            dependencies_from_list(value, path: root_path + path, groups: groups)
          end
        end

        sig do
          params(
            settings: T::Hash[String, Object],
            root_path: T::Array[T.any(String, Integer)],
            groups: T::Array[String]
          ).returns(T::Array[Dependabot::Dependency])
        end
        def compiler_plugin_dependencies(settings, root_path:, groups:)
          path = %w(kotlin compilerPlugins)
          plugins = dig_value(settings, path)
          return [] unless plugins.is_a?(Array)

          plugins.each_with_index.filter_map do |plugin, index|
            next unless plugin.is_a?(Hash)

            dependency = plugin["dependency"]
            next unless dependency.is_a?(String)

            dependency_from_scalar(
              dependency,
              path: root_path + path + [index, "dependency"],
              groups: groups + ["plugins"]
            )
          end
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def project_maven_plugins
          plugins = parsed["mavenPlugins"]
          return [] unless plugins.is_a?(Array)

          dependencies_from_list(plugins, path: ["mavenPlugins"], groups: %w(dependencies plugins))
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def maven_plugin_extra_dependencies
          plugins = parsed["mavenPlugins"]
          return [] unless plugins.is_a?(Hash)

          result = T.let([], T::Array[Dependabot::Dependency])
          plugins.each do |goal, configuration|
            next unless configuration.is_a?(Hash)

            dependencies = configuration["dependencies"]
            next unless dependencies.is_a?(Array)

            result.concat(
              dependencies_from_list(
                dependencies,
                path: ["mavenPlugins", goal, "dependencies"],
                groups: %w(dependencies plugins)
              )
            )
          end
          result
        end

        sig do
          params(
            values: T::Array[Object],
            path: T::Array[T.any(String, Integer)],
            groups: T::Array[String]
          ).returns(T::Array[Dependabot::Dependency])
        end
        def dependencies_from_list(values, path:, groups:)
          values.each_with_index.filter_map do |value, index|
            item_path = path + [index]
            case value
            when String
              dependency_from_scalar(value, path: item_path, groups: groups)
            when Hash
              dependency_from_mapping(
                value,
                path: item_path,
                groups: groups
              )
            end
          end
        end

        sig do
          params(
            mapping: T::Hash[Object, Object],
            path: T::Array[T.any(String, Integer)],
            groups: T::Array[String]
          ).returns(T.nilable(Dependabot::Dependency))
        end
        def dependency_from_mapping(mapping, path:, groups:)
          bom = mapping["bom"]
          if bom.is_a?(String)
            return dependency_from_scalar(
              bom,
              path: path + ["bom"],
              groups: groups + ["bom"]
            )
          end

          key = mapping.keys.find { |candidate| candidate.is_a?(String) && coordinate(candidate) }
          return unless key.is_a?(String)

          details = coordinate(key)
          return unless details

          dependency_from(
            name: "#{details.fetch(:group)}:#{details.fetch(:artifact)}",
            version: details.fetch(:version),
            groups: groups,
            metadata: {
              kind: "yaml_key",
              path: path + [key],
              value: key,
              coordinate: details.fetch(:coordinate),
              profile: profile.name
            }
          )
        end

        sig do
          params(
            value: String,
            path: T::Array[T.any(String, Integer)],
            groups: T::Array[String]
          ).returns(T.nilable(Dependabot::Dependency))
        end
        def dependency_from_scalar(value, path:, groups:)
          details = coordinate(value)
          return unless details

          dependency_from(
            name: "#{details.fetch(:group)}:#{details.fetch(:artifact)}",
            version: details.fetch(:version),
            groups: groups,
            metadata: {
              kind: "yaml_value",
              path: path,
              value: value,
              coordinate: details.fetch(:coordinate),
              profile: profile.name
            }
          )
        end

        sig { params(value: String).returns(T.nilable(T::Hash[Symbol, String])) }
        def coordinate(value)
          stripped = value.strip
          return if stripped.start_with?("$", "./", "../", "//")

          stripped = stripped.delete_prefix("bom:").strip
          parts = stripped.split(":")
          return if parts.length < 3

          group, artifact, version = parts.first(3)
          return unless group&.match?(/\A[A-Za-z0-9_.-]+\z/)
          return unless artifact&.match?(/\A[A-Za-z0-9_.-]+\z/)
          return unless version && Version.correct?(version)

          {
            group: group,
            artifact: artifact,
            version: version,
            coordinate: "#{group}:#{artifact}:#{version}"
          }
        end

        sig do
          params(
            name: String,
            version: String,
            groups: T::Array[String],
            metadata: T::Hash[Symbol, Object],
            source: T.nilable(T::Hash[Symbol, String])
          ).returns(Dependabot::Dependency)
        end
        def dependency_from(name:, version:, groups:, metadata:, source: nil)
          Dependabot::Dependency.new(
            name: name,
            version: version,
            requirements: [{
              requirement: version,
              file: file.name,
              groups: groups,
              source: source,
              metadata: metadata
            }],
            package_manager: ECOSYSTEM,
            metadata: { profile: profile.name }
          )
        end

        sig { params(definition: CompatibilityProfile::BuiltIn).returns(T.nilable(T::Hash[Symbol, String])) }
        def source_for(definition)
          repository = definition[:repository]
          return unless repository.is_a?(String)

          { type: "maven_repo", url: repository }
        end

        sig do
          params(
            hash: T::Hash[String, Object],
            path: T::Array[String]
          ).returns(Object)
        end
        def dig_value(hash, path)
          path.reduce(T.let(hash, Object)) do |value, key|
            break nil unless value.is_a?(Hash)

            value[key]
          end
        end
      end
    end
  end
end
