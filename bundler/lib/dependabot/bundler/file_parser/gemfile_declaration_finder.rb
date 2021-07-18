# frozen_string_literal: true

require "parser/current"
require "dependabot/bundler/file_parser"

module Dependabot
  module Bundler
    class FileParser
      # Checks whether a dependency is declared in a Gemfile
      class GemfileDeclarationFinder
        def initialize(gemfile:)
          @gemfile = gemfile
          @declaration_nodes = {}
        end

        def gemfile_includes_dependency?(dependency)
          !declaration_node(dependency).nil?
        end

        def enhanced_req_string(dependency)
          return unless gemfile_includes_dependency?(dependency)

          fallback_string = dependency.fetch("requirement")
          req_nodes = declaration_node(dependency).children[3..-1]
          req_nodes = req_nodes.reject { |child| child.type == :hash }

          return fallback_string if req_nodes.none?
          return fallback_string unless req_nodes.all? { |n| n.type == :str }

          original_req_string = req_nodes.map { |n| n.children.last }
          fallback_requirement =
            Gem::Requirement.new(fallback_string.split(", "))
          if fallback_requirement == Gem::Requirement.new(original_req_string)
            original_req_string.join(", ")
          else
            fallback_string
          end
        end

        private

        attr_reader :gemfile

        def parsed_gemfile
          @parsed_gemfile ||= Parser::CurrentRuby.parse(gemfile.content)
        end

        def declaration_node(dependency)
          return @declaration_nodes[dependency] if @declaration_nodes.key?(dependency)
          return unless parsed_gemfile

          @declaration_nodes[dependency] = nil
          parsed_gemfile.children.any? do |node|
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
          return false unless node.children[1] == :gem

          node.children[2].children.first == dependency.fetch("name")
        end
      end
    end
  end
end
