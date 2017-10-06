# frozen_string_literal: true

require "parser/current"
require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class GitPinReplacer
          attr_reader :dependency, :new_pin

          def initialize(dependency:, new_pin:)
            @dependency = dependency
            @new_pin = new_pin
          end

          def rewrite(content)
            buffer = Parser::Source::Buffer.new("(gemfile_content)")
            buffer.source = content
            ast = Parser::CurrentRuby.new.parse(buffer)

            Rewriter.
              new(dependency: dependency, new_pin: new_pin).
              rewrite(buffer, ast)
          end

          class Rewriter < Parser::Rewriter
            PIN_KEYS = %i(ref tag).freeze
            attr_reader :dependency, :new_pin

            def initialize(dependency:, new_pin:)
              @dependency = dependency
              @new_pin = new_pin
            end

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

            def declares_targeted_gem?(node)
              return false unless node.children[1] == :gem
              node.children[2].children.first == dependency.name
            end

            def key_from_hash_pair(node)
              node.children.first.children.first.to_sym
            end

            def update_value(hash_pair)
              value_node = hash_pair.children.last
              open_quote_character, close_quote_character =
                extract_quote_characters_from(value_node)

              replace(
                value_node.loc.expression,
                %(#{open_quote_character}#{new_pin}#{close_quote_character})
              )
            end

            def extract_quote_characters_from(value_node)
              [value_node.loc.begin.source, value_node.loc.end.source]
            end
          end
        end
      end
    end
  end
end
