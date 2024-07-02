# typed: strict
# frozen_string_literal: true

require "pathname"
require "parser/current"
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
          ast = Parser::CurrentRuby.parse(file.content)
          find_require_relative_paths(ast) + find_eval_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { params(node: T.untyped).returns(T::Array[String]) }
        def find_require_relative_paths(node)
          return [] unless node.is_a?(Parser::AST::Node)

          if declares_require_relative?(node)
            return [] unless node.children[2].type == :str

            path = node.children[2].loc.expression.source.gsub(/['"]/, "")
            path = File.join(current_dir, path) unless current_dir.nil?
            path += ".rb" unless path.end_with?(".rb")
            return [Pathname.new(path).cleanpath.to_path]
          end

          node.children.flat_map do |child_node|
            find_require_relative_paths(child_node)
          end
        end

        sig { params(node: T.untyped).returns(T::Array[String]) }
        def find_eval_paths(node)
          return [] unless node.is_a?(Parser::AST::Node)

          if declares_eval?(node)
            eval_arg = node.children[2]
            if eval_arg.is_a?(Parser::AST::Node)
              file_read_node = find_file_read_node(eval_arg)
              path = extract_path_from_file_read(file_read_node) if file_read_node
              return [path] if path
            end
          end

          node.children.flat_map do |child_node|
            find_eval_paths(child_node)
          end
        end

        sig { params(node: Parser::AST::Node).returns(T.nilable(Parser::AST::Node)) }
        def find_file_read_node(node)
          return nil unless node.is_a?(Parser::AST::Node)

          # Check if the node represents a method call (:send)
          # and if the method name is :read
          method_name = node.children[1]
          receiver_node = node.children[0]

          if node.type == :send && method_name == :read && receiver_node.is_a?(Parser::AST::Node)
            # Check if the receiver of the :read method call is :File
            receiver_const = receiver_node.children[1]
            return node if receiver_const == :File
          end

          # Recursively search for a file read node in the children
          node.children.each do |child|
            next unless child.is_a?(Parser::AST::Node)

            result = find_file_read_node(child)
            return result if result
          end

          nil
        end

        sig { params(node: Parser::AST::Node).returns(T.nilable(String)) }
        def extract_path_from_file_read(node)
          return nil unless node.is_a?(Parser::AST::Node)

          expand_path_node = node.children[2]
          if expand_path_node.type == :send && expand_path_node.children[1] == :expand_path
            path_node = expand_path_node.children[2]
            return path_node.loc.expression.source.gsub(/['"]/, "") if path_node.type == :str
          end
          nil
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(file.name.rpartition("/").first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Parser::AST::Node).returns(T::Boolean) }
        def declares_require_relative?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :require_relative
        end

        sig { params(node: Parser::AST::Node).returns(T::Boolean) }
        def declares_eval?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :eval
        end
      end
    end
  end
end
