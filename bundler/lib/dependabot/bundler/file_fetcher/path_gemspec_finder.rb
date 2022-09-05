# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/bundler/file_fetcher"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileFetcher
      # Finds the paths of any gemspecs declared using `path: ` in the
      # passed Gemfile.
      class PathGemspecFinder
        def initialize(gemfile:)
          @gemfile = gemfile
        end

        def path_gemspec_paths
          ast = Parser::CurrentRuby.parse(gemfile.content)
          find_path_gemspec_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, gemfile.path
        end

        private

        attr_reader :gemfile

        def find_path_gemspec_paths(node)
          return [] unless node.is_a?(Parser::AST::Node)

          if declares_path_dependency?(node)
            path_node = path_node_for_gem_declaration(node)

            unless path_node.type == :str
              path = gemfile.path
              msg = "Dependabot only supports uninterpolated string arguments " \
                    "for path dependencies. Got " \
                    "`#{path_node.loc.expression.source}`"
              raise Dependabot::DependencyFileNotParseable.new(path, msg)
            end

            path = path_node.loc.expression.source.gsub(/['"]/, "")
            return [clean_path(path)]
          end

          node.children.flat_map do |child_node|
            find_path_gemspec_paths(child_node)
          end
        end

        def current_dir
          @current_dir ||= gemfile.name.rpartition("/").first
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        def declares_path_dependency?(node)
          return false unless node.is_a?(Parser::AST::Node)
          return false unless node.children[1] == :gem

          !path_node_for_gem_declaration(node).nil?
        end

        def clean_path(path)
          if Pathname.new(path).absolute?
            base_path = Pathname.new(File.expand_path(Dir.pwd))
            path = Pathname.new(path).relative_path_from(base_path).to_s
          end
          path = File.join(current_dir, path) unless current_dir.nil?
          Pathname.new(path).cleanpath
        end

        def path_node_for_gem_declaration(node)
          return unless node.children.last.type == :hash

          kwargs_node = node.children.last

          path_hash_pair =
            kwargs_node.children.
            find { |hash_pair| key_from_hash_pair(hash_pair) == :path }

          return unless path_hash_pair

          path_hash_pair.children.last
        end

        def key_from_hash_pair(node)
          node.children.first.children.first.to_sym
        end
      end
    end
  end
end
