# frozen_string_literal: true

require "parser/current"
require "dependabot/file_parsers/ruby/bundler"

module Dependabot
  module FileParsers
    module Ruby
      class Bundler
        class GemfileChecker
          def initialize(dependency:, gemfile:)
            @dependency = dependency
            @gemfile = gemfile
          end

          def includes_dependency?
            Parser::CurrentRuby.parse(gemfile.content).children.any? do |node|
              deep_check_for_gem(node)
            end
          end

          private

          attr_reader :dependency, :gemfile

          def deep_check_for_gem(node)
            return true if declares_targeted_gem?(node)
            return false unless node.is_a?(Parser::AST::Node)
            node.children.any? do |child_node|
              deep_check_for_gem(child_node)
            end
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
end
