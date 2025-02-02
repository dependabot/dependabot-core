# typed: strict
# frozen_string_literal: true

require "parser/current"
require "sorbet-runtime"

require "dependabot/file_parsers/base"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      # Checks whether a dependency is declared in a gemspec file
      class GemspecDeclarationFinder
        extend T::Sig

        sig { params(gemspec: Dependabot::DependencyFile).void }
        def initialize(gemspec:)
          @gemspec = gemspec
          @declaration_nodes = T.let({}, T::Hash[T::Hash[String, String], T.nilable(Parser::AST::Node)])
        end

        sig { params(dependency: T::Hash[String, String]).returns(T::Boolean) }
        def gemspec_includes_dependency?(dependency)
          !declaration_node(dependency).nil?
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :gemspec

        sig { returns(T.nilable(Parser::AST::Node)) }
        def parsed_gemspec
          @parsed_gemspec ||= T.let(Parser::CurrentRuby.parse(gemspec.content), T.nilable(Parser::AST::Node))
        end

        sig { params(dependency: T::Hash[String, String]).returns(T.nilable(Parser::AST::Node)) }
        def declaration_node(dependency)
          return @declaration_nodes[dependency] if @declaration_nodes.key?(dependency)
          return unless parsed_gemspec

          @declaration_nodes[dependency] = nil
          T.must(parsed_gemspec).children.any? do |node|
            @declaration_nodes[dependency] = deep_search_for_gem(node, dependency)
          end
          @declaration_nodes[dependency]
        end

        sig { params(node: T.untyped, dependency: T::Hash[String, String]).returns(T.nilable(Parser::AST::Node)) }
        def deep_search_for_gem(node, dependency)
          return T.cast(node, Parser::AST::Node) if declares_targeted_gem?(node, dependency)
          return unless node.is_a?(Parser::AST::Node)

          declaration_node = T.let(nil, T.nilable(Parser::AST::Node))
          node.children.find do |child_node|
            declaration_node = deep_search_for_gem(child_node, dependency)
          end
          declaration_node
        end

        sig { params(node: T.untyped, dependency: T::Hash[String, String]).returns(T::Boolean) }
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
