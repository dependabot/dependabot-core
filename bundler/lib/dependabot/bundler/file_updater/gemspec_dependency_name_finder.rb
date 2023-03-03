# typed: strict
# frozen_string_literal: true

require "parser/current"
require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GemspecDependencyNameFinder
        extend T::Sig

        ChildNode = T.type_alias { T.nilable(T.any(Parser::AST::Node, Symbol, String, Integer, Float)) }

        sig { returns(String) }
        attr_reader :gemspec_content

        sig { params(gemspec_content: String).void }
        def initialize(gemspec_content:)
          @gemspec_content = gemspec_content
        end

        # rubocop:disable Security/Eval
        sig { returns(T.nilable(String)) }
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

        sig { params(node: ChildNode).returns(T.nilable(Parser::AST::Node)) }
        def find_dependency_name_node(node)
          return unless node.is_a?(Parser::AST::Node)
          return node if declares_dependency_name?(node)

          node.children.find do |cn|
            dependency_name_node = find_dependency_name_node(cn)
            break dependency_name_node if dependency_name_node
          end
        end

        sig { params(node: ChildNode).returns(T::Boolean) }
        def declares_dependency_name?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :name=
        end
      end
    end
  end
end
