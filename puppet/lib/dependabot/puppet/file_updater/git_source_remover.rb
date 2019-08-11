# frozen_string_literal: true

require "parser/current"
require "dependabot/puppet/file_updater"

module Dependabot
  module Puppet
    class FileUpdater
      class GitSourceRemover
        attr_reader :dependency

        def initialize(dependency:)
          @dependency = dependency
        end

        def rewrite(content)
          buffer = Parser::Source::Buffer.new("(puppetfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          Rewriter.new(dependency: dependency).rewrite(buffer, ast)
        end

        class Rewriter < Parser::TreeRewriter
          attr_reader :dependency

          def initialize(dependency:)
            @dependency = dependency
          end

          def on_send(node)
            return unless declares_targeted_module?(node)
            return unless node.children.last.type == :hash

            remove_all_kwargs(node)
          end

          private

          def declares_targeted_module?(node)
            return false unless node.children[1] == :mod

            node.children[2].children.first == dependency.name
          end

          def remove_all_kwargs(node)
            kwargs_node = node.children.last

            range_to_remove =
              kwargs_node.loc.expression.join(node.children[-2].loc.end.end)

            remove(range_to_remove)
          end
        end
      end
    end
  end
end
