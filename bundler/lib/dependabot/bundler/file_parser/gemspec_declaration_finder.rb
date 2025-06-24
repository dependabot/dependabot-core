# typed: strict
# frozen_string_literal: true

require "prism"
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
          @declaration_nodes = T.let({}, T::Hash[T::Hash[String, String], T.nilable(Prism::Node)])
        end

        sig { params(dependency: T::Hash[String, String]).returns(T::Boolean) }
        def gemspec_includes_dependency?(dependency)
          !declaration_node(dependency).nil?
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :gemspec

        sig { returns(T.nilable(Prism::Node)) }
        def parsed_gemspec
          @parsed_gemspec ||= T.let(Prism.parse(gemspec.content).value, T.nilable(Prism::Node))
        end

        sig { params(dependency: T::Hash[String, String]).returns(T.nilable(Prism::Node)) }
        def declaration_node(dependency)
          return @declaration_nodes[dependency] if @declaration_nodes.key?(dependency)
          return unless parsed_gemspec

          @declaration_nodes[dependency] = nil
          T.must(parsed_gemspec).child_nodes.any? do |node|
            @declaration_nodes[dependency] = deep_search_for_gem(node, dependency)
          end
          @declaration_nodes[dependency]
        end

        sig { params(node: T.untyped, dependency: T::Hash[String, String]).returns(T.nilable(Prism::Node)) }
        def deep_search_for_gem(node, dependency)
          return unless node.is_a?(Prism::Node)
          return T.cast(node, Prism::CallNode) if declares_targeted_gem?(node, dependency)

          declaration_node = T.let(nil, T.nilable(Prism::Node))
          node.child_nodes.find do |child_node|
            declaration_node = deep_search_for_gem(child_node, dependency)
          end
          declaration_node
        end

        sig { params(node: T.untyped, dependency: T::Hash[String, String]).returns(T::Boolean) }
        def declares_targeted_gem?(node, dependency)
          return false unless node.is_a?(Prism::CallNode)

          second_child = node.name
          allowed_declarations = %i(add_dependency add_runtime_dependency add_development_dependency)
          return false unless allowed_declarations.include?(second_child)

          gem_name_node = node.arguments&.child_nodes&.first
          return false unless gem_name_node.is_a?(Prism::StringNode)

          gem_name_node.unescaped == dependency.fetch("name")
        end
      end
    end
  end
end
