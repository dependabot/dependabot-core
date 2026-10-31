# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "parser"
require "prism"
require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GitPinReplacer
        extend T::Sig

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(String) }
        attr_reader :new_pin

        sig { params(dependency: Dependabot::Dependency, new_pin: String).void }
        def initialize(dependency:, new_pin:)
          @dependency = dependency
          @new_pin = new_pin
        end

        sig { params(content: String).returns(String) }
        def rewrite(content)
          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Prism::Translation::ParserCurrent.new.parse(buffer)

          Rewriter
            .new(dependency: dependency, new_pin: new_pin)
            .rewrite(buffer, ast)
        end

        class Rewriter < Parser::TreeRewriter
          extend T::Sig

          PIN_KEYS = %i(ref tag).freeze
          GIT_BLOCK_METHODS = %i(git github).freeze

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(String) }
          attr_reader :new_pin

          sig { params(dependency: Dependabot::Dependency, new_pin: String).void }
          def initialize(dependency:, new_pin:)
            super()
            @dependency = dependency
            @new_pin = new_pin
          end

          sig { params(node: Parser::AST::Node).void }
          def on_send(node)
            return unless declares_targeted_gem?(node)

            update_pins(node)
          end

          sig { params(node: Parser::AST::Node).void }
          def on_block(node)
            update_pins(node.children.first) if git_block_declaring_targeted_gem?(node)

            super
          end

          private

          sig { params(node: Parser::AST::Node).void }
          def update_pins(node)
            kwargs_node = node.children.last
            return unless kwargs_node.is_a?(Parser::AST::Node) && kwargs_node.type == :hash

            kwargs_node.children.each do |hash_pair|
              next unless PIN_KEYS.include?(key_from_hash_pair(hash_pair))

              update_value(hash_pair)
            end
          end

          sig { params(node: Parser::AST::Node).returns(T::Boolean) }
          def declares_targeted_gem?(node)
            return false unless node.children[1] == :gem

            node.children[2].children.first == dependency.name
          end

          sig { params(node: Parser::AST::Node).returns(T::Boolean) }
          def git_block_declaring_targeted_gem?(node)
            send_node, _args, body = node.children
            return false unless send_node.type == :send
            return false unless send_node.children[0].nil? && GIT_BLOCK_METHODS.include?(send_node.children[1])

            block_statements(body).any? do |statement|
              statement.type == :send && declares_targeted_gem?(statement)
            end
          end

          sig { params(body: T.nilable(Parser::AST::Node)).returns(T::Array[Parser::AST::Node]) }
          def block_statements(body)
            return [] if body.nil?
            return body.children.grep(Parser::AST::Node) if body.type == :begin

            [body]
          end

          sig { params(node: Parser::AST::Node).returns(Symbol) }
          def key_from_hash_pair(node)
            node.children.first.children.first.to_sym
          end

          sig { params(hash_pair: Parser::AST::Node).void }
          def update_value(hash_pair)
            value_node = hash_pair.children.last
            open_quote_character, close_quote_character =
              extract_quote_characters_from(value_node)

            replace(
              value_node.loc.expression,
              %(#{open_quote_character}#{new_pin}#{close_quote_character})
            )
          end

          sig { params(value_node: Parser::AST::Node).returns([String, String]) }
          def extract_quote_characters_from(value_node)
            [value_node.loc.begin.source, value_node.loc.end.source]
          end
        end
      end
    end
  end
end
