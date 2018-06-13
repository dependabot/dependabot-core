# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/file_fetchers/ruby/bundler"
require "dependabot/errors"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler
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

          # rubocop:disable Security/Eval
          def find_child_gemfile_paths(node)
            return [] unless node.is_a?(Parser::AST::Node)

            if declares_eval_gemfile?(node)
              # We use eval here, but we know what we're doing. The FileFetchers
              # helper method should only ever be run in an isolated environment
              source = node.children[2].loc.expression.source
              begin
                path = eval(source)
              rescue StandardError
                return []
              end
              if Pathname.new(path).absolute?
                base_path = Pathname.new(File.expand_path(Dir.pwd))
                path = Pathname.new(path).relative_path_from(base_path).to_s
              end
              path = File.join(current_dir, path) unless current_dir.nil?
              return [Pathname.new(path).cleanpath.to_path]
            end

            node.children.flat_map do |child_node|
              find_child_gemfile_paths(child_node)
            end
          end
          # rubocop:enable Security/Eval

          def current_dir
            @current_dir ||= gemfile.name.split("/")[0..-2].last
          end

          def declares_eval_gemfile?(node)
            return false unless node.is_a?(Parser::AST::Node)
            node.children[1] == :eval_gemfile
          end
        end
      end
    end
  end
end
