# frozen_string_literal: true

require "parser"

module ProjectFixtures
  class Autocorrector < Parser::TreeRewriter
    attr_reader :filename, :nodes, :buffer

    def initialize(filename, nodes, project_name)
      @filename = filename
      @project_name = project_name
      @nodes = nodes
      @buffer = Parser::Source::Buffer.new("(#{filename})")
      buffer.source = File.read(filename)

      super()
    end

    def correct
      File.open(filename, "w") do |file|
        file.write(rewrite(buffer, Parser::CurrentRuby.new.parse(buffer)))
      end
    end

    def on_block(node)
      target_node = nodes.any? do |offense_node|
        # TODO: replace_with_project_fixture(dir) if node == file_node
        node == offense_node && node.location.line == offense_node.location.line
      end

      if target_node
        if files_node?(node)
          replace(
            removal_range(node),
            "let(:#{let_name(node)}) { project_dependency_files(\"#{@project_name}\") }"
          )
        else
          remove(removal_range(node))
        end
      end

      super
    end

    private

    def files_node?(node)
      Finder::FILE_NAMES.include?(let_name(node))
    end

    def let_name(node)
      send, = *node
      _, _, name = *send
      name.children.last
    end

    # This corrects for cases which contains heredocs which do not get removed in all cases if we
    # just use the `expression` range.
    def removal_range(node)
      Parser::Source::Range.new(
        buffer,
        node.location.expression.begin_pos,
        range_end(node)
      )
    end

    def range_end(node)
      location = node.location.expression

      last_line    = location.last_line
      end_location = location.end

      walk(node) do |child|
        child_location = child.location

        next unless child_location.respond_to?(:heredoc_end)

        heredoc_end = child_location.heredoc_end

        if heredoc_end.last_line > last_line
          last_line    = heredoc_end.last_line
          end_location = heredoc_end
        end
      end

      end_location.end_pos
    end

    def walk(node, &block)
      yield node

      node.children.each do |child|
        next unless child.is_a?(::Parser::AST::Node)

        walk(child, &block)
      end
    end
  end
end
