# frozen_string_literal: true

require "parser/current"
require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class GemspecSanitizer
          attr_reader :replacement_version

          def initialize(replacement_version:)
            @replacement_version = replacement_version
          end

          def rewrite(content)
            buffer = Parser::Source::Buffer.new("(gemspec_content)")
            buffer.source = content
            ast = Parser::CurrentRuby.new.parse(buffer)

            Rewriter.
              new(replacement_version: replacement_version).
              rewrite(buffer, ast)
          end

          class Rewriter < Parser::TreeRewriter
            def initialize(replacement_version:)
              @replacement_version = replacement_version
            end

            def on_send(node)
              remove(node.loc.expression) if requires_file?(node)
              replace_constant(node) if node_assigns_to_version_constant?(node)
            end

            private

            attr_reader :replacement_version

            def requires_file?(node)
              %i(require require_relative).include?(node.children[1])
            end

            def node_assigns_to_version_constant?(node)
              return false unless node.is_a?(Parser::AST::Node)
              return false unless node.children.first.is_a?(Parser::AST::Node)
              return false unless node.children.first&.type == :lvar

              return true if node.children[1] == :version=
              return true if node_is_version_constant?(node.children.last)
              return true if node_calls_version_constant?(node.children.last)
              node_interpolates_version_constant?(node.children.last)
            end

            def node_is_version_constant?(node)
              return false unless node.is_a?(Parser::AST::Node)
              return false unless node.type == :const
              node.children.last.to_s.match?(/version/i)
            end

            def node_calls_version_constant?(node)
              return false unless node.is_a?(Parser::AST::Node)
              return false unless node.type == :send
              node.children.any? { |n| node_is_version_constant?(n) }
            end

            def node_interpolates_version_constant?(node)
              return false unless node.is_a?(Parser::AST::Node)
              return false unless node.type == :dstr

              node.children.
                select { |n| n.type == :begin }.
                flat_map(&:children).
                any? { |n| node_is_version_constant?(n) }
            end

            def replace_constant(node)
              case node.children.last&.type
              when :str then nil # no-op
              when :const, :send, :lvar
                replace(
                  node.children.last.loc.expression,
                  %("#{replacement_version}")
                )
              when :dstr
                node.children.last.children.
                  select { |n| n.type == :begin }.
                  flat_map(&:children).
                  select { |n| node_is_version_constant?(n) }.
                  each do |n|
                    replace(
                      n.loc.expression,
                      %("#{replacement_version}")
                    )
                  end
              else
                raise "Unexpected node type #{node.children.last&.type}"
              end
            end
          end
        end
      end
    end
  end
end
