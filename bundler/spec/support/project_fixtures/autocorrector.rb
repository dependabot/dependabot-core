# frozen_string_literal: true

require "parser"

module ProjectFixtures
  class Autocorrector < Parser::TreeRewriter
    attr_reader :filename, :nodes, :buffer

    def initialize(filename, nodes, project_name, start_loc)
      @filename = filename
      @project_name = project_name
      @start_loc = start_loc
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
      if node.location.line == @start_loc
        replace(
          block_range(node),
          # We put in a comment on the same line that we split out later, as to
          # not change the line numbering which we need to preserve until we
          # processed all specs. There may very well be a much better way to do
          # this, but I don't know how.
          node.loc.expression.source.split("\n").tap do |lines|
            lines[0] = if lines[0].start_with?("its")
                         "let(:dependency_files) { project_dependency_files(\"#{@project_name}\") }" + " # #{lines[0]}"
                       else
                         lines[0] + " # let(:dependency_files) { project_dependency_files(\"#{@project_name}\") }"
                       end
          end.join("\n")
        )

        return super
      end

      target_node = nodes.any? do |offense_node|
        node == offense_node && node.loc.line == offense_node.loc.line &&
          # TODO: Why are we sent nodes that are not tracked?
          Finder::TRACKED_LETS.include?(let_name(node))
      end

      return super unless target_node

      replace(
        block_range(node),
        node.loc.expression.source + " # pragma:delete"
      )

      super
    end

    private

    def let_name(node)
      send, = *node
      _, _, name = *send
      name.children.last
    end

    def block_range(node)
      Parser::Source::Range.new(
        buffer,
        node.loc.expression.begin_pos,
        node.loc.expression.end_pos
      )
    end
  end
end
