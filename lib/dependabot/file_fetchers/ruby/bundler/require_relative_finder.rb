# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/file_fetchers/ruby/bundler"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler
        # Finds the paths of any files included using `require_relative` in the
        # passed file.
        class RequireRelativeFinder
          def initialize(file:)
            @file = file
          end

          def require_relative_paths
            ast = Parser::CurrentRuby.parse(file.content)
            find_require_relative_paths(ast)
          end

          private

          attr_reader :file

          # rubocop:disable Security/Eval
          def find_require_relative_paths(node)
            return [] unless node.is_a?(Parser::AST::Node)

            if declares_require_relative?(node)
              # We use eval here, but we know what we're doing. The FileFetchers
              # helper method should only ever be run in an isolated environment
              source = node.children[2].loc.expression.source
              begin
                path = eval(source)
              rescue StandardError
                return []
              end

              path = File.join(current_dir, path) unless current_dir.nil?
              return [Pathname.new(path + ".rb").cleanpath.to_path]
            end

            node.children.flat_map do |child_node|
              find_require_relative_paths(child_node)
            end
          end
          # rubocop:enable Security/Eval

          def current_dir
            @current_dir ||= file.name.split("/")[0..-2].last
          end

          def declares_require_relative?(node)
            return false unless node.is_a?(Parser::AST::Node)
            node.children[1] == :require_relative
          end
        end
      end
    end
  end
end
