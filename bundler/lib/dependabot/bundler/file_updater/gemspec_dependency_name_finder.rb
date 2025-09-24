# typed: strict
# frozen_string_literal: true

require "prism"
require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GemspecDependencyNameFinder
        extend T::Sig

        sig { returns(String) }
        attr_reader :gemspec_content

        sig { params(gemspec_content: String).void }
        def initialize(gemspec_content:)
          @gemspec_content = gemspec_content
        end

        # rubocop:disable Security/Eval
        sig { returns(T.nilable(String)) }
        def dependency_name
          result = Prism.parse(gemspec_content)
          dependency_name_node = find_dependency_name_node(result.value)
          return unless dependency_name_node.is_a?(Prism::CallNode)

          arg_node = dependency_name_node.arguments&.arguments&.first
          return if arg_node.nil?

          begin
            eval(arg_node.slice)
          rescue StandardError
            nil # If we can't evaluate the expression just return nil
          end
        end
        # rubocop:enable Security/Eval

        private

        sig { params(node: T.nilable(Prism::Node)).returns(T.nilable(Prism::Node)) }
        def find_dependency_name_node(node)
          return unless node.is_a?(Prism::Node)
          return node if declares_dependency_name?(node)

          node.child_nodes.find do |cn|
            dependency_name_node = find_dependency_name_node(cn)
            break dependency_name_node if dependency_name_node
          end
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def declares_dependency_name?(node)
          return false unless node.is_a?(Prism::CallNode)

          node.name == :name=
        end
      end
    end
  end
end
