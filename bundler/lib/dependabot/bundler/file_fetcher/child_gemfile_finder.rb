# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/bundler/file_fetcher"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileFetcher
      # Finds the paths of any Gemfiles declared using `eval_gemfile` in the
      # passed Gemfile.
      class ChildGemfileFinder
        def initialize(gemfile:)
          @gemfile = gemfile
        end

        def child_gemfile_paths
          ast = Parser::CurrentRuby.parse(gemfile.content)
          find_child_gemfile_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, gemfile.path
        end

        private

        attr_reader :gemfile

        def find_child_gemfile_paths(node)
          return [] unless node.is_a?(Parser::AST::Node)

          if declares_eval_gemfile?(node)
            path_node = node.children[2]
            unless path_node.type == :str
              path = gemfile.path
              msg = "Dependabot only supports uninterpolated string arguments "\
                    "to eval_gemfile. Got "\
                    "`#{path_node.loc.expression.source}`"
              raise Dependabot::DependencyFileNotParseable.new(path, msg)
            end

            path = path_node.loc.expression.source.gsub(/['"]/, "")
            path = File.join(current_dir, path) unless current_dir.nil?
            return [Pathname.new(path).cleanpath.to_path]
          end

          node.children.flat_map do |child_node|
            find_child_gemfile_paths(child_node)
          end
        end

        def current_dir
          @current_dir ||= gemfile.name.rpartition("/").first
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        def declares_eval_gemfile?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :eval_gemfile
        end
      end
    end
  end
end
