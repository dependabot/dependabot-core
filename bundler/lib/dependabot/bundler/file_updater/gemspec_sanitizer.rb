# typed: true
# frozen_string_literal: true

require "parser/current"
require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GemspecSanitizer
        UNNECESSARY_ASSIGNMENTS = %i(
          bindir=
          cert_chain=
          email=
          executables=
          extra_rdoc_files=
          date=
          homepage=
          license=
          licenses=
          metadata=
          post_install_message=
          rdoc_options=
        ).freeze

        attr_reader :replacement_version

        def initialize(replacement_version:)
          @replacement_version = replacement_version
        end

        def rewrite(content)
          buffer = Parser::Source::Buffer.new("(gemspec_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          updated_content =
            Rewriter
            .new(replacement_version: replacement_version)
            .rewrite(buffer, ast)

          # Remove any constants from strings
          updated_content.gsub(
            /#\{[A-Z][^.}]*::[A-Z][^.}]*\}/,
            '#{"' + replacement_version.to_s + '"}'
          )
        end

        class Rewriter < Parser::TreeRewriter
          def initialize(replacement_version:)
            @replacement_version = replacement_version
          end

          def on_send(node)
            # Wrap any `require` or `require_relative` calls in a rescue
            # block, as we might not have the required files
            wrap_require(node) if requires_file?(node)

            # Remove any assignments to a VERSION constant (or similar), as
            # that constant probably comes from a required file
            replace_version_assignments(node)

            # Replace the `s.files= ...` assignment with a blank array, as
            # occasionally a File.open(..).readlines pattern is used
            replace_file_assignments(node)

            # Replace the `s.require_path= ...` assignment, as
            # occasionally a Dir['lib'] pattern is used
            replace_require_paths_assignments(node)

            # Replace any `File.read(...)` calls with a dummy string
            replace_file_reads(node)

            # Replace any `JSON.parse(...)` calls with a dummy hash
            replace_json_parses(node)

            # Remove the arguments from any `Find.find(...)` calls
            remove_find_dot_find_args(node)

            remove_unnecessary_assignments(node)
          end

          private

          attr_reader :replacement_version

          def requires_file?(node)
            %i(require require_relative).include?(node.children[1])
          end

          def wrap_require(node)
            replace(
              node.loc.expression,
              "begin\n" \
              "#{node.loc.expression.source_line}\n" \
              "rescue LoadError\n" \
              "end"
            )
          end

          def replace_version_assignments(node)
            return unless node.is_a?(Parser::AST::Node)

            return replace_constant(node) if node_assigns_to_version_constant?(node)

            node.children.each { |child| replace_version_assignments(child) }
          end

          def replace_version_constant_references(node)
            return unless node.is_a?(Parser::AST::Node)

            return replace(node.loc.expression, %("#{replacement_version}")) if node_is_version_constant?(node)

            node.children.each do |child|
              replace_version_constant_references(child)
            end
          end

          def replace_file_assignments(node)
            return unless node.is_a?(Parser::AST::Node)

            return replace_file_assignment(node) if node_assigns_files_to_var?(node)

            node.children.each { |child| replace_file_assignments(child) }
          end

          def replace_require_paths_assignments(node)
            return unless node.is_a?(Parser::AST::Node)

            return replace_require_paths_assignment(node) if node_assigns_require_paths?(node)

            node.children.each do |child|
              replace_require_paths_assignments(child)
            end
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

          def node_assigns_files_to_var?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)
            return false unless node.children.first&.type == :lvar
            return false unless node.children[1] == :files=

            node_dynamically_lists_files?(node.children[2])
          end

          def node_dynamically_lists_files?(node)
            return false unless node.is_a?(Parser::AST::Node)

            return true if node.type == :send

            node.type == :block && node.children.first&.type == :send
          end

          def node_assigns_require_paths?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)
            return false unless node.children.first&.type == :lvar

            node.children[1] == :require_paths=
          end

          def replace_file_reads(node)
            return unless node.is_a?(Parser::AST::Node)
            return if node.children[1] == :version=
            return replace_file_read(node) if node_reads_a_file?(node)
            return replace_file_readlines(node) if node_uses_readlines?(node)

            node.children.each { |child| replace_file_reads(child) }
          end

          def node_reads_a_file?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)
            return false unless node.children.first&.type == :const
            return false unless node.children.first.children.last == :File

            node.children[1] == :read
          end

          def node_uses_readlines?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)
            return false unless node.children.first&.type == :const
            return false unless node.children.first.children.last == :File

            node.children[1] == :readlines
          end

          def replace_json_parses(node)
            return unless node.is_a?(Parser::AST::Node)
            return if node.children[1] == :version=
            return replace_json_parse(node) if node_parses_json?(node)

            node.children.each { |child| replace_json_parses(child) }
          end

          def node_parses_json?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)
            return false unless node.children.first&.type == :const
            return false unless node.children.first.children.last == :JSON

            node.children[1] == :parse
          end

          def remove_find_dot_find_args(node)
            return unless node.is_a?(Parser::AST::Node)
            return if node.children[1] == :version=
            return remove_find_args(node) if node_calls_find_dot_find?(node)

            node.children.each { |child| remove_find_dot_find_args(child) }
          end

          def node_calls_find_dot_find?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)
            return false unless node.children.first&.type == :const
            return false unless node.children.first.children.last == :Find

            node.children[1] == :find
          end

          def remove_unnecessary_assignments(node)
            return unless node.is_a?(Parser::AST::Node)

            if unnecessary_assignment?(node) && node_includes_heredoc?(node)
              range_to_remove = node.loc.expression.join(find_heredoc_end_range(node))
              return replace(range_to_remove, '"sanitized"')
            elsif unnecessary_assignment?(node)
              return replace(node.loc.expression, '"sanitized"')
            end

            node.children.each do |child|
              remove_unnecessary_assignments(child)
            end
          end

          def node_includes_heredoc?(node)
            find_heredoc_end_range(node)
          end

          # Performs a depth-first search for the first heredoc in the given
          # Parser::AST::Node.
          #
          # Returns a Parser::Source::Range identifying the location of the end
          #   of the heredoc, or nil if no heredoc was found.
          def find_heredoc_end_range(node)
            return unless node.is_a?(Parser::AST::Node)

            node.children.each do |child|
              next unless child.is_a?(Parser::AST::Node)

              return child.location.heredoc_end if child.location.respond_to?(:heredoc_end)

              range = find_heredoc_end_range(child)
              return range if range
            end

            nil
          end

          def unnecessary_assignment?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.children.first.is_a?(Parser::AST::Node)

            return true if node.children.first.type == :lvar &&
                           UNNECESSARY_ASSIGNMENTS.include?(node.children[1])

            node.children[1] == :[]= && node.children.first.children.last
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

            node.children
                .select { |n| n.type == :begin }
                .flat_map(&:children)
                .any? { |n| node_is_version_constant?(n) }
          end

          def replace_constant(node)
            case node.children.last&.type
            when :str, :int then nil # no-op
            when :float, :const, :send, :lvar, :if, :dstr
              replace(
                node.children.last.loc.expression,
                %("#{replacement_version}")
              )
            else
              raise "Unexpected node type #{node.children.last&.type}"
            end
          end

          def replace_file_assignment(node)
            replace(node.children.last.loc.expression, "[]")
          end

          def replace_require_paths_assignment(node)
            replace(node.children.last.loc.expression, "['lib']")
          end

          def replace_file_read(node)
            replace(node.loc.expression, %("#{replacement_version}"))
          end

          def replace_json_parse(node)
            replace(
              node.loc.expression,
              %({ "version" => "#{replacement_version}" })
            )
          end

          def replace_file_readlines(node)
            replace(node.loc.expression, %(["#{replacement_version}"]))
          end

          def remove_find_args(node)
            last_arg = node.children.last

            range_to_remove =
              last_arg.loc.expression.join(node.children[2].loc.begin.begin)

            remove(range_to_remove)
          end
        end
      end
    end
  end
end
