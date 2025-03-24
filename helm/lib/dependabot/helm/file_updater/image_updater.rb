# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"
require "yaml"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      class UpdateImages
        extend T::Sig
        extend T::Helpers

        sig { params(dependency: Dependency, dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency:, dependency_files:)
          @dependency_files = dependency_files
          @dependency = dependency
        end

        sig { params(file_name: String).returns(T.nilable(String)) }
        def updated_values_yaml_content(file_name)
          content = @dependency_files.find { |f| f.name.match?(file_name) }.content
          yaml_stream = YAML.parse_stream(content)

          update_image_tags_recursive(yaml_stream, content)
        end

        private

        attr_reader :dependency_files
        attr_reader :dependency

        sig { params(yaml_stream: Psych::Nodes::Stream, content: String).returns(String) }
        def update_image_tags_recursive(yaml_stream, content)
          updated_content = content.dup

          yaml_stream.children.each do |document|
            document.children.each do |root_node|
              updated_content = find_and_update_images(root_node, updated_content.split("\n"))
            end
          end

          updated_content.join("\n")
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
          0.step(node.children.length - 1, 2) do |i|
            key_node = node.children[i]
            value_node = node.children[i + 1]
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
          node.children.each do |child|
            content = find_and_update_images(child, content)
          end
          content
        end

        sig { params(key: String, value_node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_image_key(key, value_node, content)
          return content unless key == "image" && value_node.is_a?(Psych::Nodes::Mapping)

          dependency_name = T.must(dependency).name
          dependency_version = T.must(dependency).version
          dependency_requirements = T.must(dependency).requirements

          has_dependency = value_node.children.any? { |n| n.value == dependency_name }
          return content unless has_dependency

          dependency_requirements.each do |req|
            next unless req[:metadata][:type] == :docker_image

            version_scalar = value_node.children.find { |n| n.value == req[:source][:tag] }
            next unless version_scalar

            line = version_scalar.start_line
            content[line] = content[line].gsub(req[:source][:tag], dependency_version)
          end

          content
        end
      end
    end
  end
end
