# frozen_string_literal: true

require "parser/current"
require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class GemspecDependencyNameFinder
          attr_reader :gemspec_content

          def initialize(gemspec_content:)
            @gemspec_content = gemspec_content
          end

          # rubocop:disable Security/Eval
          def dependency_name
            ast = Parser::CurrentRuby.parse(gemspec_content)
            dependency_name_node = find_dependency_name_node(ast)
            return unless dependency_name_node

            begin
              eval(dependency_name_node.children[2].loc.expression.source)
            rescue StandardError
              nil # If we can't evaluate the expression just return nil
            end
          end
          # rubocop:enable Security/Eval

          private

          def find_dependency_name_node(node)
            return unless node.is_a?(Parser::AST::Node)
            return node if declares_dependency_name?(node)
            node.children.find do |cn|
              dependency_name_node = find_dependency_name_node(cn)
              break dependency_name_node if dependency_name_node
            end
          end

          def declares_dependency_name?(node)
            return false unless node.is_a?(Parser::AST::Node)
            node.children[1] == :name=
          end
        end
      end
    end
  end
end
