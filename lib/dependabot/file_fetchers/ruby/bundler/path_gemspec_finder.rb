# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/file_fetchers/ruby/bundler"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler
        # Finds the paths of any gemspecs declared using `path: ` in the
        # passed Gemfile.
        class PathGemspecFinder
          def initialize(gemfile:)
            @gemfile = gemfile
          end

          def path_gemspec_paths
            ast = Parser::CurrentRuby.parse(gemfile.content)
            find_path_gemspec_paths(ast)
          end

          private

          attr_reader :gemfile

          # rubocop:disable Security/Eval
          def find_path_gemspec_paths(node)
            return [] unless node.is_a?(Parser::AST::Node)

            if declares_path_dependency?(node)
              path_node = path_node_for_gem_declaration(node)

              begin
                # We use eval here, but we know what we're doing. The
                # FileFetchers helper method should only ever be run in an
                # isolated environment
                path = eval(path_node.loc.expression.source)
              rescue StandardError
                return []
              end
              return [clean_path(path)]
            end

            relevant_child_nodes(node).flat_map do |child_node|
              find_path_gemspec_paths(child_node)
            end
          end
          # rubocop:enable Security/Eval

          def current_dir
            @current_dir ||= gemfile.name.split("/")[0..-2].last
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

          # rubocop:disable Security/Eval
          def relevant_child_nodes(node)
            return [] unless node.is_a?(Parser::AST::Node)
            return node.children unless node.type == :if

            begin
              if eval(node.children.first.loc.expression.source)
                [node.children[1]]
              else
                [node.children[2]]
              end
            rescue StandardError
              return node.children
            end
          end
          # rubocop:enable Security/Eval

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
end
