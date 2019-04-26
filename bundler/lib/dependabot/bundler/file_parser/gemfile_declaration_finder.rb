# frozen_string_literal: true

require "parser/current"
require "dependabot/bundler/file_parser"

module Dependabot
  module Bundler
    class FileParser
      # Checks whether a dependency is declared in a Gemfile
      class GemfileDeclarationFinder
        def initialize(dependency:, gemfile:)
          @dependency = dependency
          @gemfile = gemfile
        end

        def gemfile_includes_dependency?
          !declaration_node.nil?
        end

        def enhanced_req_string
          return unless gemfile_includes_dependency?

          fallback_string = dependency.requirement.to_s
          req_nodes = declaration_node.children[3..-1]
          req_nodes = req_nodes.reject { |child| child.type == :hash }

          return fallback_string if req_nodes.none?
          return fallback_string unless req_nodes.all? { |n| n.type == :str }

          original_req_string = req_nodes.map { |n| n.children.last }
          if dependency.requirement == Gem::Requirement.new(original_req_string)
            original_req_string.join(", ")
          else
            fallback_string
          end
        end

        private

        attr_reader :dependency, :gemfile

        def declaration_node
          return @declaration_node if defined?(@declaration_node)
          return unless Parser::CurrentRuby.parse(gemfile.content)

          @declaration_node = nil
          Parser::CurrentRuby.parse(gemfile.content).children.any? do |node|
            @declaration_node = deep_search_for_gem(node)
          end
          @declaration_node
        end

        def deep_search_for_gem(node)
          return node if declares_targeted_gem?(node)
          return unless node.is_a?(Parser::AST::Node)

          declaration_node = nil
          node.children.find do |child_node|
            declaration_node = deep_search_for_gem(child_node)
          end
          declaration_node
        end

        def declares_targeted_gem?(node)
          return false unless node.is_a?(Parser::AST::Node)
          return false unless node.children[1] == :gem

          node.children[2].children.first == dependency.name
        end
      end
    end
  end
end
