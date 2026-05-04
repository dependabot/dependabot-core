# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "yaml"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      class ImageUpdater
        extend T::Sig
        extend T::Helpers

        sig { params(dependency: Dependency, dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency:, dependency_files:)
          @dependency_files = dependency_files
          @dependency = dependency
        end

        sig { params(file_name: String).returns(T.nilable(String)) }
        def updated_values_yaml_content(file_name)
          value_file = dependency_files.find { |f| f.name.match?(file_name) }
          raise "Expected a values.yaml file to exist!" if value_file.nil?

          content = value_file.content
          yaml_stream = YAML.parse_stream(T.must(content))

          update_image_tags_recursive(yaml_stream, T.must(content))
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { params(yaml_stream: Psych::Nodes::Stream, content: String).returns(String) }
        def update_image_tags_recursive(yaml_stream, content)
          # Use a -1 limit so split preserves trailing empty fields. Without
          # this, "foo\n".split("\n") returns ["foo"] and the join below drops
          # the trailing newline, producing a spurious diff that masks the
          # "no change" guard below.
          updated_content = content.dup.split("\n", -1)

          yaml_stream.children.each do |document|
            document.children.each do |root_node|
              updated_content = find_and_update_images(root_node, updated_content)
            end
          end

          updated_content = updated_content.join("\n")

          raise "Expected content to change!" if content == updated_content

          updated_content
        end

        sig { params(node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def find_and_update_images(node, content)
          if node.is_a?(Psych::Nodes::Mapping)
            content = process_mapping_node(node, content)
          elsif node.is_a?(Psych::Nodes::Sequence)
            content = process_sequence_node(node, content)
          end

          content
        end

        sig { params(node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_mapping_node(node, content)
          node.children.each_slice(2) do |key_node, value_node|
            next unless key_node.is_a?(Psych::Nodes::Scalar)

            key = key_node.value
            content = process_image_key(key, value_node, content)

            if value_node.is_a?(Psych::Nodes::Mapping) || value_node.is_a?(Psych::Nodes::Sequence)
              content = find_and_update_images(value_node, content)
            end
          end
          content
        end

        sig { params(node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_sequence_node(node, content)
          node.children.reduce(content) do |updated_content, child|
            find_and_update_images(child, updated_content)
          end
        end

        sig { params(key: String, value_node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_image_key(key, value_node, content)
          return content unless key == "image" && value_node.is_a?(Psych::Nodes::Mapping)

          dependency_name = dependency.name
          has_dependency = contains_dependency?(value_node, dependency_name)
          return content unless has_dependency

          dependency_version = T.must(dependency.version)
          update_version_tags(value_node, content, dependency_version)
        end

        sig { params(node: Psych::Nodes::Node, dependency_name: String).returns(T::Boolean) }
        def contains_dependency?(node, dependency_name)
          node.children.any? do |child|
            child.is_a?(Psych::Nodes::Scalar) && child.value == dependency_name
          end
        end

        sig do
          params(
            value_node: Psych::Nodes::Mapping,
            content: T::Array[String],
            dependency_version: String
          ).returns(T::Array[String])
        end
        def update_version_tags(value_node, content, dependency_version)
          dependency.requirements.each do |req|
            next unless req[:metadata][:type] == :docker_image

            tag_value = req[:source][:tag]
            next if tag_value.nil?

            # The YAML scalar may be either the bare tag (e.g. "v1.6.41") or a
            # digest-pinned tag (e.g. "v1.6.41@sha256:..."). Match both shapes
            # so digest-pinned values still get updated. The digest portion is
            # left intact -- we don't have a new digest to swap in here, and
            # silently dropping the user's pin would be worse than producing a
            # clearly-stale digest the user can refresh manually.
            version_scalar = value_node.children.find do |node|
              next false unless node.is_a?(Psych::Nodes::Scalar)

              node.value == tag_value || node.value.start_with?("#{tag_value}@")
            end

            next unless version_scalar

            line = version_scalar.start_line
            old_scalar = version_scalar.value
            new_scalar = old_scalar.sub(tag_value, dependency_version)
            content[line] = T.must(content[line]).sub(old_scalar, new_scalar)
          end

          content
        end
      end
    end
  end
end
