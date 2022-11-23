# frozen_string_literal: true

require "parser/current"

module Dependabot
  module Bundler
    class FileParser
      # Checks whether a dependency is declared in a gemspec file
      class GemspecDeclarationFinder
        def initialize(gemspec:)
          @gemspec = gemspec
          @declaration_nodes = {}
        end

        def gemspec_includes_dependency?(dependency)
          !declaration_node(dependency).nil?
        end

        private

        attr_reader :gemspec

        def parsed_gemspec
          @parsed_gemspec ||= Parser::CurrentRuby.parse(gemspec.content)
        end

        def declaration_node(dependency)
          return @declaration_nodes[dependency] if @declaration_nodes.key?(dependency)
          return unless parsed_gemspec

          @declaration_nodes[dependency] = nil
          parsed_gemspec.children.any? do |node|
            @declaration_nodes[dependency] = deep_search_for_gem(node, dependency)
          end
          @declaration_nodes[dependency]
        end

        def deep_search_for_gem(node, dependency)
          return node if declares_targeted_gem?(node, dependency)
          return unless node.is_a?(Parser::AST::Node)

          declaration_node = nil
          node.children.find do |child_node|
            declaration_node = deep_search_for_gem(child_node, dependency)
          end
          declaration_node
        end

        def declares_targeted_gem?(node, dependency)
          return false unless node.is_a?(Parser::AST::Node)

          second_child = node.children[1]
          allowed_declarations = %i(add_dependency add_runtime_dependency add_development_dependency)
          return false unless allowed_declarations.include?(second_child)

          node.children[2].children.first == dependency.fetch("name")
        end
      end
    end
  end
end
