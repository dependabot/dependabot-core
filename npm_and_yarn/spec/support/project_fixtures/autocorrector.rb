# frozen_string_literal: true

require "parser"

module ProjectFixtures
  TRACKER = Hash.new { false }

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
        # TODO: This messes up the indentation, rubocop can autofix this for us,
        # but would be nice to figure out how to determine it. Breadcrumb:
        # https://github.com/rubocop-hq/rubocop/blob/751edc7bf3df93d7ec5d59f5ac5b501627a6b723/lib/rubocop/cop/layout/heredoc_indentation.rb#L144-L155
        child = node.children[-1].children.select { |n| n.type.equal?(:block) }.first
        insert_before(
          # This is gross, but we know this is a block, so the second child will
          # be the actual block. Its children are the content of that block, and
          # we want to insert before the first line in the block, ensuring that
          # the first thing the block defines is a files definition.
          block_range(child),
          "let(:dependency_files) { project_dependency_files(\"#{@project_name}\") }\n"
        )
        return super
      end

      target_node = nodes.any? do |offense_node|
        node == offense_node && node.loc.line == offense_node.loc.line &&
          # TODO: Why are we sent nodes that are not tracked?
          Finder::TRACKED_LETS.include?(let_name(node))
      end

      return super unless target_node && !TRACKER[node]

      remove(block_range(node))

      TRACKER[node] = true

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
