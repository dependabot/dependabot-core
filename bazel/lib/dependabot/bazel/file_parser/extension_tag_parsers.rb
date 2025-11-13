# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_parser"

module Dependabot
  module Bazel
    class FileParser
      module ExtensionTagParsers
        extend T::Sig

        sig do
          params(
            tag: StarlarkParser::ExtensionTag,
            file: Dependabot::DependencyFile
          ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def parse_go_module_tag(tag, file)
          path = tag.arguments["path"]
          version = tag.arguments["version"]
          sum = tag.arguments["sum"]

          return nil unless path.is_a?(String) && version.is_a?(String)

          {
            name: path,
            version: version,
            requirements: [
              {
                file: file.name,
                requirement: version,
                groups: ["go_deps"],
                source: {
                  type: "go_modules",
                  sum: sum.is_a?(String) ? sum : nil
                },
                metadata: { line: tag.line }
              }
            ],
            package_manager: "bazel"
          }
        end

        sig do
          params(
            tag: StarlarkParser::ExtensionTag,
            file: Dependabot::DependencyFile
          ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def parse_maven_artifact_tag(tag, file)
          group = tag.arguments["group"]
          artifact = tag.arguments["artifact"]
          version = tag.arguments["version"]

          return nil unless group.is_a?(String) && artifact.is_a?(String) && version.is_a?(String)

          {
            name: "#{group}:#{artifact}",
            version: version,
            requirements: [
              {
                file: file.name,
                requirement: version,
                groups: ["maven"],
                source: {
                  type: "maven",
                  group: group,
                  artifact: artifact
                },
                metadata: { line: tag.line }
              }
            ],
            package_manager: "bazel"
          }
        end

        sig do
          params(
            tag: StarlarkParser::ExtensionTag,
            file: Dependabot::DependencyFile
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def parse_maven_install_tag(tag, file)
          artifacts = tag.arguments["artifacts"]
          return [] unless artifacts.is_a?(Array)

          dependencies = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

          artifacts.each do |artifact_string|
            next unless artifact_string.is_a?(String)

            # Parse Maven coordinate string format: "group:artifact:version"
            parts = artifact_string.split(":")
            next unless parts.length >= 3

            group = parts[0]
            artifact = parts[1]
            version = parts[2]

            dependencies << {
              name: "#{group}:#{artifact}",
              version: version,
              requirements: [
                {
                  file: file.name,
                  requirement: version,
                  groups: ["maven"],
                  source: {
                    type: "maven",
                    group: group,
                    artifact: artifact,
                    coordinate_string: artifact_string
                  },
                  metadata: { line: tag.line }
                }
              ],
              package_manager: "bazel"
            }
          end

          dependencies
        end

        sig do
          params(
            tag: StarlarkParser::ExtensionTag,
            file: Dependabot::DependencyFile
          ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def parse_cargo_spec_tag(tag, file)
          package = tag.arguments["package"]
          version = tag.arguments["version"]

          return nil unless package.is_a?(String) && version.is_a?(String)

          features = tag.arguments["features"]
          default_features = tag.arguments["default_features"]

          {
            name: package,
            version: version,
            requirements: [
              {
                file: file.name,
                requirement: version,
                groups: ["crate"],
                source: {
                  type: "cargo",
                  features: features.is_a?(Array) ? features : [],
                  default_features: default_features
                },
                metadata: { line: tag.line }
              }
            ],
            package_manager: "bazel"
          }
        end
      end
    end
  end
end
