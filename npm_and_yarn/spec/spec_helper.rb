# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

require_relative "./support/project_fixtures"

require "parser/current"

def walk(node, &block)
  yield node

  node.children.each do |child|
    next unless child.is_a?(::Parser::AST::Node)

    walk(child, &block)
  end
end

RSpec.configure do |c|
  c.after do
    next unless ENV["AUTOFIX_PROJECT_FIXTURES"]

    ProjectFixtures::Finder.storage.each do |_, data|
      dir = ProjectFixtures::Builder.new(data).run

      source_map = Hash.new { [] }

      file = data.lets.first.file
      raw_source = Pathname.new(file).read
      parser = Parser::CurrentRuby.new(Parser::Builders::Default.new)
      buffer = Parser::Source::Buffer.new(file, source: raw_source)
      parsed_source = parser.parse(buffer)

      walk(parsed_source) do |node|
        next unless node.loc.expression

        source_map[node.loc.first_line] <<= node
      end

      nodes = data.lets.flat_map do |let|
        block_nodes = source_map.fetch(let.line, []).select { |node| node.type.equal?(:block) }

        block_nodes.select do |node|
          send, = *node
          _receiver, selector = *send

          selector.equal?(:let)
        end
      end

      ProjectFixtures::Autocorrector.new(file, nodes, dir).correct
    end
  end
end
