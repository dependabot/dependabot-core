# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/errors"

module Dependabot
  module Nix
    class Lockfile
      extend T::Sig

      Node = T.type_alias { T::Hash[String, Object] }

      require_relative "lockfile/dependency_input"

      class FollowsPath < T::ImmutableStruct
        extend T::Sig

        const :head, String
        const :tail, T::Array[String]

        sig { params(value: Object).returns(T.nilable(FollowsPath)) }
        def self.from_value(value)
          return unless value.is_a?(Array)

          segments = value.grep(String)
          head = segments.first
          return unless head && segments.length == value.length

          new(head: head, tail: segments.drop(1))
        end

        sig { returns(T::Array[String]) }
        def segments
          [head, *tail]
        end
      end
      private_constant :FollowsPath

      sig { params(file: Dependabot::DependencyFile).returns(Lockfile) }
      def self.from_file(file)
        new(T.must(file.content), path: file.path)
      rescue JSON::ParserError, TypeError => e
        raise Dependabot::DependencyFileNotParseable.new(file.path, e.message)
      end

      sig { params(content: String, path: String).void }
      def initialize(content, path: "flake.lock")
        value = T.cast(JSON.parse(content), Object)
        raise TypeError, "#{path} must be an object" unless value.is_a?(Hash)

        @data = T.let(value, Node)
        @path = path
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

        FollowsPath.from_value(reference)&.segments
      end

      sig { params(input_name: String).returns(T.nilable(Node)) }
      def input_node(input_name)
        label = resolve_reference(root_inputs[input_name], T.let(Set.new, T::Set[String]))
        return unless label

        node = nodes[label]
        node if node.is_a?(Hash)
      end

      sig { params(input_name: String).returns(T.nilable(DependencyInput)) }
      def dependency_input(input_name)
        node = input_node(input_name)
        InputParser.new(node, path: @path, name: input_name).parse if node
      end

      sig { params(input_name: String).returns(T.nilable(Node)) }
      def original_source(input_name)
        original = input_node(input_name)&.fetch("original", nil)
        original if original.is_a?(Hash)
      end

      sig { params(input_name: String).returns(T.nilable(Node)) }
      def locked_source(input_name)
        locked = input_node(input_name)&.fetch("locked", nil)
        locked if locked.is_a?(Hash)
      end

      sig { params(input_name: String).returns(T.nilable(String)) }
      def locked_revision(input_name)
        locked = locked_source(input_name)
        return unless locked

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

        path = FollowsPath.from_value(reference)
        return unless path

        path_key = path.segments.join("\0")
        return if visited_paths.include?(path_key)

        visited_paths.add(path_key)
        resolve_path(path, visited_paths)
      end

      sig { params(path: FollowsPath, visited_paths: T::Set[String]).returns(T.nilable(String)) }
      def resolve_path(path, visited_paths)
        reference = T.let(root_inputs[path.head], Object)

        segments = path.tail
        index = T.let(0, Integer)
        while index < segments.length
          segment = segments.fetch(index)
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
    end
  end
end
