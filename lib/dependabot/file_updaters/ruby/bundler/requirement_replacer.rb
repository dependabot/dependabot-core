# frozen_string_literal: true

require "parser/current"
require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class RequirementReplacer
          attr_reader :dependency, :filename

          def initialize(dependency:, filename:)
            @dependency = dependency
            @filename = filename
          end

          def rewrite(content)
            buffer = Parser::Source::Buffer.new("(gemfile_content)")
            buffer.source = content
            ast = Parser::CurrentRuby.new.parse(buffer)

            Rewriter.new(
              dependency: dependency,
              filename: filename
            ).rewrite(buffer, ast)
          end

          class Rewriter < Parser::Rewriter
            SKIPPED_TYPES = %i(send lvar dstr).freeze

            def initialize(dependency:, filename:)
              @dependency = dependency
              @filename = filename

              return if filename == "Gemfile" || filename.end_with?(".gemspec")
              raise "File must be a Gemfile or gemspec"
            end

            def on_send(node)
              return unless declares_targeted_gem?(node)

              req_nodes = node.children[3..-1]
              req_nodes = req_nodes.reject { |child| child.type == :hash }

              return if req_nodes.none?
              return if req_nodes.any? { |n| SKIPPED_TYPES.include?(n.type) }

              quote_character = extract_quote_character_from(req_nodes)

              replace(
                range_for(req_nodes),
                new_requirement_string(quote_character)
              )
            end

            private

            attr_reader :dependency, :filename

            def declaration_methods
              return %i(gem) if filename == "Gemfile"
              %i(add_dependency add_runtime_dependency
                 add_development_dependency)
            end

            def declares_targeted_gem?(node)
              return false unless declaration_methods.include?(node.children[1])
              node.children[2].children.first == dependency.name
            end

            def extract_quote_character_from(requirement_nodes)
              case requirement_nodes.first.type
              when :str, :dstr
                requirement_nodes.first.loc.begin.source
              else
                requirement_nodes.first.children.first.loc.begin.source
              end
            end

            def new_requirement_string(quote_character)
              dependency.requirements.
                find { |r| r[:file] == filename }.
                fetch(:requirement).split(",").
                map { |r| %(#{quote_character}#{r.strip}#{quote_character}) }.
                join(", ")
            end

            def range_for(nodes)
              nodes.first.loc.begin.begin.join(nodes.last.loc.expression)
            end
          end
        end
      end
    end
  end
end
