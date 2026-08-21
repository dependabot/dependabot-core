# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

module Dependabot
  module Nix
    class Lockfile
      extend T::Sig

      Node = T.type_alias { T::Hash[String, Object] }

      sig { params(content: String).void }
      def initialize(content)
        @data = T.let(T.cast(JSON.parse(content), Node), Node)
      end

      sig { returns(T.nilable(Integer)) }
      def version
        value = @data["version"]
        value if value.is_a?(Integer)
      end

      sig { returns(T::Array[String]) }
      def root_input_names
        root_inputs.keys
      end

      sig { params(input_name: String).returns(T.nilable(T::Array[String])) }
      def input_path(input_name)
        reference = root_inputs[input_name]
        return [input_name] if reference.is_a?(String)
        return unless string_array?(reference)

        T.cast(reference, T::Array[String])
      end

      sig { params(input_name: String).returns(T.nilable(Node)) }
      def input_node(input_name)
        label = resolve_reference(root_inputs[input_name], T.let(Set.new, T::Set[String]))
        return unless label

        node = nodes[label]
        node if node.is_a?(Hash)
      end

      sig { params(input_name: String).returns(T.nilable(Node)) }
      def original_source(input_name)
        original = input_node(input_name)&.fetch("original", nil)
        original if original.is_a?(Hash)
      end

      sig { params(input_name: String).returns(T.nilable(String)) }
      def locked_revision(input_name)
        locked = input_node(input_name)&.fetch("locked", nil)
        return unless locked.is_a?(Hash)

        revision = locked["rev"]
        revision if revision.is_a?(String)
      end

      private

      sig { returns(Node) }
      def nodes
        value = @data["nodes"]
        value.is_a?(Hash) ? value : {}
      end

      sig { returns(Node) }
      def root_inputs
        root_name = @data["root"]
        root_name = "root" unless root_name.is_a?(String)

        root_node = nodes[root_name]
        return {} unless root_node.is_a?(Hash)

        inputs = root_node["inputs"]
        inputs.is_a?(Hash) ? inputs : {}
      end

      sig { params(reference: Object, visited_paths: T::Set[String]).returns(T.nilable(String)) }
      def resolve_reference(reference, visited_paths)
        return reference if reference.is_a?(String)
        return unless string_array?(reference)

        path = T.cast(reference, T::Array[String])
        path_key = path.join("\0")
        return if visited_paths.include?(path_key)

        visited_paths.add(path_key)
        resolve_path(path, visited_paths)
      end

      sig { params(path: T::Array[String], visited_paths: T::Set[String]).returns(T.nilable(String)) }
      def resolve_path(path, visited_paths)
        first_segment = path.first
        return unless first_segment

        reference = T.let(root_inputs[first_segment], Object)

        index = T.let(1, Integer)
        while index < path.length
          segment = path.fetch(index)
          label = resolve_reference(reference, visited_paths)
          return unless label

          node = nodes[label]
          return unless node.is_a?(Hash)

          inputs = node["inputs"]
          return unless inputs.is_a?(Hash)

          reference = T.let(inputs[segment], Object)
          index += 1
        end

        resolve_reference(reference, visited_paths)
      end

      sig { params(value: Object).returns(T::Boolean) }
      def string_array?(value)
        value.is_a?(Array) && !value.empty? && value.all?(String)
      end
    end
  end
end
