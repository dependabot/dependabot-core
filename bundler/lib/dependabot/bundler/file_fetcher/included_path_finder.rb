# typed: strict
# frozen_string_literal: true

require "pathname"
require "prism"
require "dependabot/bundler/file_fetcher"
require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Bundler
    class FileFetcher
      # Finds the paths of any files included using `require_relative` and `eval` in the
      # passed file.
      class IncludedPathFinder
        extend T::Sig

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
        end

        sig { returns(T::Array[String]) }
        def find_included_paths
          result = Prism.parse(file.content)
          raise Dependabot::DependencyFileNotParseable, file.path if result.failure?

          find_require_relative_paths(result.value) + find_eval_paths(result.value)
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { params(node: T.untyped).returns(T::Array[String]) }
        def find_require_relative_paths(node)
          return [] if node.nil?

          if declares_require_relative?(node)
            relative_arg = node.arguments&.arguments&.first
            return [] unless relative_arg.is_a?(Prism::StringNode)

            path = relative_arg.unescaped
            path = File.join(current_dir, path) unless current_dir.nil?
            path += ".rb" unless path.end_with?(".rb")
            return [Pathname.new(path).cleanpath.to_path]
          end

          node.child_nodes.flat_map do |child_node|
            find_require_relative_paths(child_node)
          end
        end

        sig { params(node: T.untyped).returns(T::Array[String]) }
        def find_eval_paths(node)
          return [] if node.nil?

          if declares_eval?(node)
            eval_arg = node.arguments&.arguments&.first

            if eval_arg.is_a?(Prism::Node)
              file_read_node = find_file_read_node(eval_arg)
              path = extract_path_from_file_read(file_read_node) if file_read_node
              return [path] if path
            end
          end

          node.child_nodes.flat_map do |child_node|
            find_eval_paths(child_node)
          end
        end

        sig { params(node: T.nilable(Prism::Node)).returns(T.nilable(Prism::Node)) }
        def find_file_read_node(node)
          return nil unless node.is_a?(Prism::Node)

          return node if contains_receiver_node?(node)

          # Recursively search for a file read node in the children
          node.child_nodes.each do |child|
            result = find_file_read_node(child)
            return result if result
          end

          nil
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def contains_receiver_node?(node)
          return false unless node.is_a?(Prism::CallNode) && node.name == :read

          # Check if the node represents a method call (CallNode))
          # and if the method name is :read
          receiver_node = node.arguments&.arguments&.first

          # Check if the receiver of the :read method call is :File
          return false unless receiver_node.is_a?(Prism::CallNode)

          constant_node = T.cast(receiver_node.receiver, T.nilable(Prism::ConstantReadNode))
          constant_node&.name == :File
        end

        sig { params(node: Prism::Node).returns(T.nilable(String)) }
        def extract_path_from_file_read(node)
          return nil unless node.is_a?(Prism::CallNode)

          expand_path_node = node.arguments&.arguments&.first
          if expand_path_node.is_a?(Prism::CallNode) && expand_path_node.name == :expand_path
            path_node = expand_path_node.arguments&.arguments&.first
            return path_node.unescaped if path_node.is_a?(Prism::StringNode)
          end
          nil
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(file.name.rpartition("/").first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def declares_require_relative?(node)
          return false unless node.is_a?(Prism::CallNode)

          node.name == :require_relative
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def declares_eval?(node)
          return false unless node.is_a?(Prism::CallNode)

          node.name == :eval
        end
      end
    end
  end
end
