# typed: strict
# frozen_string_literal: true

require "parser/current"
require "sorbet-runtime"

require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class RequirementReplacer
        extend T::Sig

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Symbol) }
        attr_reader :file_type

        sig { returns(String) }
        attr_reader :updated_requirement

        sig { returns(T.nilable(String)) }
        attr_reader :previous_requirement

        sig do
          params(
            dependency: Dependabot::Dependency,
            file_type: Symbol,
            updated_requirement: String,
            previous_requirement: T.nilable(String),
            insert_if_bare: T::Boolean
          ).void
        end
        def initialize(dependency:, file_type:, updated_requirement:,
                       previous_requirement: nil, insert_if_bare: false)
          @dependency           = dependency
          @file_type            = file_type
          @updated_requirement  = updated_requirement
          @previous_requirement = previous_requirement
          @insert_if_bare       = insert_if_bare
        end

        sig { params(content: T.nilable(String)).returns(String) }
        def rewrite(content)
          return "" unless content

          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          updated_content = Rewriter.new(
            dependency: dependency,
            file_type: file_type,
            updated_requirement: updated_requirement,
            insert_if_bare: insert_if_bare?
          ).rewrite(buffer, ast)

          update_comment_spacing_if_required(content, updated_content)
        end

        private

        sig { returns(T::Boolean) }
        def insert_if_bare?
          @insert_if_bare
        end

        sig { params(content: String, updated_content: String).returns(String) }
        def update_comment_spacing_if_required(content, updated_content)
          return updated_content unless previous_requirement

          return updated_content if updated_content == content
          return updated_content if length_change.zero?

          updated_lines = updated_content.lines
          updated_line_index =
            updated_lines.length
                         .times.find { |i| content.lines[i] != updated_content.lines[i] }
          return updated_content unless updated_line_index

          updated_line = T.must(updated_lines[updated_line_index])

          updated_line =
            if length_change.positive?
              updated_line.sub(/(?<=\s)\s{#{length_change}}#/, "#")
            elsif length_change.negative?
              updated_line.sub(/(?<=\s{2})#/, (" " * length_change.abs) + "#")
            else
              updated_line
            end

          updated_lines[updated_line_index] = updated_line
          updated_lines.join
        end

        sig { returns(Integer) }
        def length_change
          return 0 unless previous_requirement

          prev_req = T.must(previous_requirement)
          return updated_requirement.length - prev_req.length unless prev_req.start_with?("=")

          updated_requirement.length -
            prev_req.gsub(/^=/, "").strip.length
        end

        class Rewriter < Parser::TreeRewriter
          extend T::Sig

          # TODO: Ideally we wouldn't have to ignore all of these, but
          # implementing each one will be tricky.
          SKIPPED_TYPES = T.let(%i(send lvar dstr begin if case splat const or).freeze, T::Array[Symbol])

          sig do
            params(
              dependency: Dependabot::Dependency,
              file_type: Symbol,
              updated_requirement: String,
              insert_if_bare: T::Boolean
            ).void
          end
          def initialize(dependency:, file_type:, updated_requirement:,
                         insert_if_bare:)
            @dependency = T.let(dependency, Dependabot::Dependency)
            @file_type = T.let(file_type, Symbol)
            @updated_requirement = T.let(updated_requirement, String)
            @insert_if_bare = T.let(insert_if_bare, T::Boolean)

            return if %i(gemfile gemspec).include?(file_type)

            raise "File type must be :gemfile or :gemspec. Got #{file_type}."
          end

          sig { params(node: T.untyped).void }
          def on_send(node)
            return unless declares_targeted_gem?(node)

            req_nodes = node.children[3..-1]
            req_nodes = req_nodes.reject { |child| child.type == :hash }

            return if req_nodes.none? && !insert_if_bare?
            return if req_nodes.any? { |n| SKIPPED_TYPES.include?(n.type) }

            quote_characters = extract_quote_characters_from(req_nodes)
            space_after_specifier = space_after_specifier?(req_nodes)
            use_equality_operator = use_equality_operator?(req_nodes)

            new_req = new_requirement_string(
              quote_characters: quote_characters,
              space_after_specifier: space_after_specifier,
              use_equality_operator: use_equality_operator
            )
            if req_nodes.any?
              replace(range_for(req_nodes), new_req)
            else
              insert_after(range_for(node.children[2..2]), ", #{new_req}")
            end
          end

          private

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { returns(Symbol) }
          attr_reader :file_type

          sig { returns(String) }
          attr_reader :updated_requirement

          sig { returns(T::Boolean) }
          def insert_if_bare?
            @insert_if_bare
          end

          sig { returns(T::Array[Symbol]) }
          def declaration_methods
            return %i(gem) if file_type == :gemfile

            %i(add_dependency add_runtime_dependency
               add_development_dependency)
          end

          sig { params(node: T.untyped).returns(T::Boolean) }
          def declares_targeted_gem?(node)
            return false unless declaration_methods.include?(node.children[1])

            node.children[2].children.first == dependency.name
          end

          sig { params(requirement_nodes: T::Array[T.untyped]).returns([String, String]) }
          def extract_quote_characters_from(requirement_nodes)
            return ['"', '"'] if requirement_nodes.none?

            case requirement_nodes.first.type
            when :str, :dstr, :sym
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

          sig { params(requirement_nodes: T::Array[T.untyped]).returns(T::Boolean) }
          def space_after_specifier?(requirement_nodes)
            return true if requirement_nodes.none?

            req_string =
              case requirement_nodes.first.type
              when :str, :dstr, :sym
                requirement_nodes.first.loc.expression.source
              else
                requirement_nodes.first.children.first.loc.expression.source
              end

            ops = Gem::Requirement::OPS.keys
            return true if ops.none? { |op| req_string.include?(op) }

            req_string.include?(" ")
          end

          EQUALITY_OPERATOR = /(?<![<>!])=/

          sig { params(requirement_nodes: T::Array[T.untyped]).returns(T::Boolean) }
          def use_equality_operator?(requirement_nodes)
            return true if requirement_nodes.none?

            req_string =
              case requirement_nodes.first.type
              when :str, :dstr, :sym
                requirement_nodes.first.loc.expression.source
              else
                requirement_nodes.first.children.first.loc.expression.source
              end

            req_string.match?(EQUALITY_OPERATOR)
          end

          sig do
            params(
              quote_characters: [String, String],
              space_after_specifier: T::Boolean,
              use_equality_operator: T::Boolean
            ).returns(String)
          end
          def new_requirement_string(quote_characters:,
                                     space_after_specifier:,
                                     use_equality_operator:)
            open_quote, close_quote = quote_characters
            new_requirement_string =
              updated_requirement.split(",")
                                 .map do |r|
                req_string = serialized_req(r, use_equality_operator)
                req_string = %(#{open_quote}#{req_string}#{close_quote})
                req_string = req_string.delete(" ") unless space_after_specifier
                req_string
              end.join(", ")

            new_requirement_string
          end

          sig { params(req: String, use_equality_operator: T::Boolean).returns(String) }
          def serialized_req(req, use_equality_operator)
            tmp_req = req

            # Gem::Requirement serializes exact matches as a string starting
            # with `=`. We may need to remove that equality operator if it
            # wasn't used originally.
            tmp_req = tmp_req.gsub(EQUALITY_OPERATOR, "") unless use_equality_operator

            tmp_req.strip
          end

          sig { params(nodes: T::Array[T.untyped]).returns(T.untyped) }
          def range_for(nodes)
            nodes.first.loc.begin.begin.join(nodes.last.loc.expression)
          end
        end
      end
    end
  end
end
