# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "parser/current"
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
          @dependency = T.let(dependency, Dependabot::Dependency)
          @new_pin = T.let(new_pin, String)
        end

        sig { params(content: String).returns(String) }
        def rewrite(content)
          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          Rewriter
            .new(dependency: dependency, new_pin: new_pin)
            .rewrite(buffer, ast)
        end

        class Rewriter < Parser::TreeRewriter
          extend T::Sig

          PIN_KEYS = T.let(%i(ref tag).freeze, T::Array[Symbol])

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(String) }
          attr_reader :new_pin

          sig { params(dependency: Dependabot::Dependency, new_pin: String).void }
          def initialize(dependency:, new_pin:)
            super()
            @dependency = T.let(dependency, Dependabot::Dependency)
            @new_pin = T.let(new_pin, String)
          end

          sig { params(node: Parser::AST::Node).returns(T.untyped) }
          def on_send(node)
            return unless declares_targeted_gem?(node)
            return unless node.children.last.type == :hash

            kwargs_node = node.children.last
            kwargs_node.children.each do |hash_pair|
              next unless PIN_KEYS.include?(key_from_hash_pair(hash_pair))

              update_value(hash_pair)
            end
          end

          private

          sig { params(node: Parser::AST::Node).returns(T::Boolean) }
          def declares_targeted_gem?(node)
            return false unless node.children[1] == :gem

            node.children[2].children.first == dependency.name
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
