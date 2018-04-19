# frozen_string_literal: true

require "parser/current"
require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    module Ruby
      class Bundler
        class RequirementReplacer
          attr_reader :dependency, :file_type, :updated_requirement

          def initialize(dependency:, file_type:, updated_requirement:)
            @dependency = dependency
            @file_type = file_type
            @updated_requirement = updated_requirement
          end

          def rewrite(content)
            buffer = Parser::Source::Buffer.new("(gemfile_content)")
            buffer.source = content
            ast = Parser::CurrentRuby.new.parse(buffer)

            Rewriter.new(
              dependency: dependency,
              file_type: file_type,
              updated_requirement: updated_requirement
            ).rewrite(buffer, ast)
          end

          class Rewriter < Parser::TreeRewriter
            # TODO: Ideally we wouldn't have to ignore all of these, but
            # implementing each one will be tricky.
            SKIPPED_TYPES = %i(send lvar dstr begin if splat const).freeze

            def initialize(dependency:, file_type:, updated_requirement:)
              @dependency = dependency
              @file_type = file_type
              @updated_requirement = updated_requirement

              return if %i(gemfile gemspec).include?(file_type)
              raise "File type must be :gemfile or :gemspec. Got #{file_type}."
            end

            def on_send(node)
              return unless declares_targeted_gem?(node)

              req_nodes = node.children[3..-1]
              req_nodes = req_nodes.reject { |child| child.type == :hash }

              return if req_nodes.none?
              return if req_nodes.any? { |n| SKIPPED_TYPES.include?(n.type) }

              quote_characters = extract_quote_characters_from(req_nodes)
              space_after_specifier = space_after_specifier?(req_nodes)

              replace(
                range_for(req_nodes),
                new_requirement_string(quote_characters, space_after_specifier)
              )
            end

            private

            attr_reader :dependency, :file_type, :updated_requirement

            def declaration_methods
              return %i(gem) if file_type == :gemfile
              %i(add_dependency add_runtime_dependency
                 add_development_dependency)
            end

            def declares_targeted_gem?(node)
              return false unless declaration_methods.include?(node.children[1])
              node.children[2].children.first == dependency.name
            end

            def extract_quote_characters_from(requirement_nodes)
              case requirement_nodes.first.type
              when :str, :dstr
                [
                  requirement_nodes.first.loc.begin.source,
                  requirement_nodes.first.loc.end.source
                ]
              else
                [
                  requirement_nodes.first.children.first.loc.begin.source,
                  requirement_nodes.first.children.first.loc.end.source
                ]
              end
            end

            def space_after_specifier?(requirement_nodes)
              req_string =
                case requirement_nodes.first.type
                when :str, :dstr
                  requirement_nodes.first.loc.expression.source
                else
                  requirement_nodes.first.children.first.loc.expression.source
                end

              ops = Gem::Requirement::OPS.keys
              return true if ops.none? { |op| req_string.include?(op) }
              req_string.include?(" ")
            end

            def new_requirement_string(quote_characters, space_after_specifier)
              open_quote, close_quote = quote_characters
              new_requirement_string =
                updated_requirement.split(",").
                map { |r| %(#{open_quote}#{r.strip}#{close_quote}) }.
                join(", ")

              new_requirement_string.delete!(" ") unless space_after_specifier
              new_requirement_string
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
