# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/bundler/file_fetcher"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileFetcher
      # Finds the paths of any files included using `require_relative` in the
      # passed file.
      class RequireRelativeFinder
        def initialize(file:)
          @file = file
        end

        def require_relative_paths
          ast = Parser::CurrentRuby.parse(file.content)
          find_require_relative_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        private

        attr_reader :file

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

        def current_dir
          @current_dir ||= file.name.rpartition("/").first
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        def declares_require_relative?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :require_relative
        end
      end
    end
  end
end
