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

          update_version_tags(value_node, content)
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
            content: T::Array[String]
          ).returns(T::Array[String])
        end
        def update_version_tags(value_node, content)
          dependency.requirements.each do |new_req|
            next unless new_req.dig(:metadata, :type) == :docker_image

            apply_image_requirement(new_req, value_node, content)
          end

          content
        end

        sig do
          params(
            new_req: T::Hash[Symbol, T.untyped],
            value_node: Psych::Nodes::Mapping,
            content: T::Array[String]
          ).void
        end
        def apply_image_requirement(new_req, value_node, content)
          old_req = matching_previous_requirement(new_req) || new_req
          old_tag = old_req.dig(:source, :tag)
          return if old_tag.nil?

          version_scalar = find_version_scalar(value_node, old_tag)
          return unless version_scalar

          new_tag = new_req.dig(:source, :tag) || T.must(dependency.version)
          old_digest = old_req.dig(:source, :digest)
          new_digest = new_req.dig(:source, :digest)

          old_scalar = version_scalar.value
          new_scalar = old_scalar.sub(old_tag, new_tag)
          new_scalar = new_scalar.sub(old_digest, new_digest) if old_digest && new_digest

          line = version_scalar.start_line
          content[line] = T.must(content[line]).sub(old_scalar, new_scalar)
        end

        # Match scalars of the bare tag (e.g. "v1.6.41") and the digest-pinned
        # form (e.g. "v1.6.41@sha256:..."). In the latter case the caller
        # replaces the tag and the digest in lockstep so the user's pin keeps
        # pointing at the new image.
        sig do
          params(
            value_node: Psych::Nodes::Mapping,
            old_tag: String
          ).returns(T.nilable(Psych::Nodes::Scalar))
        end
        def find_version_scalar(value_node, old_tag)
          match = value_node.children.find do |node|
            next false unless node.is_a?(Psych::Nodes::Scalar)

            node.value == old_tag || node.value.start_with?("#{old_tag}@")
          end
          T.cast(match, T.nilable(Psych::Nodes::Scalar))
        end

        sig { params(new_req: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def matching_previous_requirement(new_req)
          (dependency.previous_requirements || []).find do |req|
            req[:file] == new_req[:file] && req.dig(:metadata, :type) == :docker_image
          end
        end
      end
    end
  end
end
