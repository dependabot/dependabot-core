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
        its_block = node.loc.expression.source.start_with?("its")
        if its_block
          replace(
            block_range(node),
            node.loc.expression.source.split("\n").tap do |lines|
              lines.insert(0, "let(:dependency_files) { project_dependency_files(\"#{@project_name}\") }\n")
            end.join("\n")
          )
        else
          byebug
          replace(
            block_range(node.parent),
            node.parent.loc.expression.source.split("\n").tap do |lines|
              lines.insert(1, "let(:dependency_files) { project_dependency_files(\"#{@project_name}\") }")
            end.join("\n")
          )
        end
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
