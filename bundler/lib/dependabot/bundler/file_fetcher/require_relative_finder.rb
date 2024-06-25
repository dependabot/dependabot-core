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
      # Finds the paths of any files included using `require_relative` in the
      # passed file.
      class RequireRelativeFinder
        extend T::Sig

        sig { params(file: Dependabot::DependencyFile).void }
        def initialize(file:)
          @file = file
        end

        sig { returns(T::Array[String]) }
        def require_relative_paths
          ast = Parser::CurrentRuby.parse(file.content)
          find_require_relative_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { params(node: T.untyped).returns(T::Array[T.untyped]) }
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
      end
    end
  end
end
