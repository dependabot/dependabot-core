# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/luarocks/file_parser"

RSpec.describe Dependabot::Luarocks::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: nil,
      credentials: []
    )
  end

  let(:dependency_files) { [rockspec_file] }
  let(:rockspec_file) do
    Dependabot::DependencyFile.new(
      name: "demo.rockspec",
      content: rockspec_body
    )
  end
  let(:rockspec_body) do
    <<~ROCKSPEC
      package = "demo"
      version = "1.0.0-1"

      dependencies = {
        "lua >= 5.1",
        "luafilesystem >= 1.8.0-1",
        "luasocket"
      }

      build_dependencies = {
        "busted == 2.1.0-1"
      }
    ROCKSPEC
  end

  describe "#parse" do
    it "returns dependencies from dependency tables" do
      names = parser.parse.map(&:name)
      expect(names).to contain_exactly("lua", "luafilesystem", "luasocket", "busted")
    end

    it "preserves requirements" do
      dependency = parser.parse.find { |dep| dep.name == "luafilesystem" }
      expect(dependency.requirements.first[:requirement]).to eq(">= 1.8.0-1")
    end
  end
end
