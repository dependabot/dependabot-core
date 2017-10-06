# frozen_string_literal: true

require "parser/current"
require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class GitPinReplacer < Parser::Rewriter
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
              replace(
                hash_pair.children.last.loc.expression,
                %("#{new_pin}")
              )
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
        end
      end
    end
  end
end
