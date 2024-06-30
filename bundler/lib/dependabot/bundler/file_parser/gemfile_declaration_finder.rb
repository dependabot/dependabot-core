# typed: strict
# frozen_string_literal: true

require "parser/current"
require "sorbet-runtime"

require "dependabot/file_parsers/base"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      # Checks whether a dependency is declared in a Gemfile
      class GemfileDeclarationFinder
        extend T::Sig

        sig { params(gemfile: Dependabot::DependencyFile).void }
        def initialize(gemfile:)
          @gemfile = gemfile
          @declaration_nodes = T.let({}, T::Hash[T::Hash[String, String], T.nilable(Parser::AST::Node)])
        end

        sig { params(dependency: T::Hash[String, String]).returns(T::Boolean) }
        def gemfile_includes_dependency?(dependency)
          !declaration_node(dependency).nil?
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(dependency: T::Hash[String, String]).returns(T.nilable(String)) }
        def enhanced_req_string(dependency)
          return unless gemfile_includes_dependency?(dependency)

          fallback_string = dependency.fetch("requirement")
          req_nodes = declaration_node(dependency)&.children&.[](3..-1)
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
        # rubocop:enable Metrics/PerceivedComplexity

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :gemfile

        sig { returns(T.nilable(Parser::AST::Node)) }
        def parsed_gemfile
          @parsed_gemfile ||= T.let(
            Parser::CurrentRuby.parse(gemfile.content),
            T.nilable(Parser::AST::Node)
          )
        end

        sig { params(dependency: T::Hash[String, String]).returns(T.nilable(Parser::AST::Node)) }
        def declaration_node(dependency)
          return @declaration_nodes[dependency] if @declaration_nodes.key?(dependency)
          return unless parsed_gemfile

          @declaration_nodes[dependency] = nil
          T.must(parsed_gemfile).children.any? do |node|
            @declaration_nodes[dependency] = deep_search_for_gem(node, dependency)
          end
          @declaration_nodes[dependency]
        end

        sig do
          params(
            node: T.untyped,
            dependency: T::Hash[String, String]
          )
            .returns(T.nilable(Parser::AST::Node))
        end
        def deep_search_for_gem(node, dependency)
          return T.cast(node, Parser::AST::Node) if declares_targeted_gem?(node, dependency)
          return unless node.is_a?(Parser::AST::Node)

          declaration_node = T.let(nil, T.nilable(Parser::AST::Node))
          node.children.find do |child_node|
            declaration_node = deep_search_for_gem(child_node, dependency)
          end
          declaration_node
        end

        sig do
          params(
            node: T.untyped,
            dependency: T::Hash[String, String]
          )
            .returns(T::Boolean)
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
