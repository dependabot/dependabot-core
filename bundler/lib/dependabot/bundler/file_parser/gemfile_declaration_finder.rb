# typed: strict
# frozen_string_literal: true

require "prism"
require "sorbet-runtime"

require "dependabot/bundler/file_parser"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      # Checks whether a dependency is declared in a Gemfile
      class GemfileDeclarationFinder
        extend T::Sig

        sig { params(gemfile: Dependabot::DependencyFile).void }
        def initialize(gemfile:)
          @gemfile = gemfile
          @declaration_nodes = T.let({}, T::Hash[String, T.nilable(Prism::Node)])
        end

        sig { params(dependency_name: String).returns(T::Boolean) }
        def gemfile_includes_dependency?(dependency_name)
          !declaration_node(dependency_name).nil?
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(dependency_name: String, fallback_string: String).returns(T.nilable(String)) }
        def enhanced_req_string(dependency_name, fallback_string)
          return unless gemfile_includes_dependency?(dependency_name)

          call_node = declaration_node(dependency_name)
          return fallback_string unless call_node.is_a?(Prism::CallNode)

          req_nodes = call_node.arguments&.arguments&.[](1..-1) || []
          req_nodes = req_nodes.reject { |child| child.is_a?(Prism::HashNode) || child.is_a?(Prism::KeywordHashNode) }

          return fallback_string if req_nodes.none?
          return fallback_string unless req_nodes.all?(Prism::StringNode)

          original_req_string = T.cast(req_nodes, T::Array[Prism::StringNode]).map(&:unescaped)
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

        sig { returns(T.nilable(Prism::Node)) }
        def parsed_gemfile
          @parsed_gemfile ||= T.let(
            Prism.parse(gemfile.content).value,
            T.nilable(Prism::Node)
          )
        end

        sig { params(dependency_name: String).returns(T.nilable(Prism::Node)) }
        def declaration_node(dependency_name)
          return @declaration_nodes[dependency_name] if @declaration_nodes.key?(dependency_name)
          return unless parsed_gemfile

          @declaration_nodes[dependency_name] = nil
          T.must(parsed_gemfile).child_nodes.any? do |node|
            @declaration_nodes[dependency_name] = deep_search_for_gem(node, dependency_name)
          end
          @declaration_nodes[dependency_name]
        end

        sig do
          params(
            node: T.nilable(Prism::Node),
            dependency_name: String
          )
            .returns(T.nilable(Prism::Node))
        end
        def deep_search_for_gem(node, dependency_name)
          return unless node.is_a?(Prism::Node)
          return node if declares_targeted_gem?(node, dependency_name)

          declaration_node = T.let(nil, T.nilable(Prism::Node))
          node.child_nodes.find do |child_node|
            declaration_node = deep_search_for_gem(child_node, dependency_name)
          end
          declaration_node
        end

        sig do
          params(
            node: T.nilable(Prism::Node),
            dependency_name: String
          )
            .returns(T::Boolean)
        end
        def declares_targeted_gem?(node, dependency_name)
          return false unless node.is_a?(Prism::CallNode)
          return false unless node.name == :gem

          gem_name_node = node.arguments&.arguments&.first
          return false unless gem_name_node.is_a?(Prism::StringNode)

          gem_name_node.unescaped == dependency_name
        end
      end
    end
  end
end
