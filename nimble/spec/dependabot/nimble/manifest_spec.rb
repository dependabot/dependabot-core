# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nimble/manifest"

RSpec.describe Dependabot::Nimble::Manifest do
  subject(:manifest) { described_class.new(content) }

  let(:content) { fixture("example.nimble") }

  def fixture(name) = File.read(File.join(__dir__, "fixtures", name))

  describe "#requires" do
    it "finds every string of every call, in order" do
      expect(manifest.requires.map { |entry| [entry.name, entry.requirement, entry.task] }).to eq(
        [
          ["nim", ">= 2.0.0", nil],
          ["chronos", ">= 4.0.4", nil],
          ["bearssl", "", nil],
          ["unittest2", "~= 0.2.0", nil],
          ["pinned", "== 1.2.3", nil],
          ["ranged", ">= 1.0 & < 2.0", nil],
          ["branchy", "#main", nil],
          ["balls", "^= 5.0", "test"]
        ]
      )
    end

    it "ignores a call in a comment" do
      expect(manifest.requires.map(&:name)).not_to include("commented")
    end

    it "gives offsets that cut out exactly the requirement" do
      manifest.requires.reject { |entry| entry.requirement.empty? }.each do |entry|
        expect(content[entry.requirement_start...entry.requirement_end]).to eq(entry.requirement)
      end
    end

    it "reads a call written with parentheses" do
      expect(described_class.new(%(requires("foo >= 1.0")\n)).requires.map(&:name)).to eq(["foo"])
    end

    it "reads a call written in a block" do
      content = %(when defined(windows):\n  requires "winapi >= 2.0"\n)
      expect(described_class.new(content).requires.map(&:name)).to eq(["winapi"])
    end

    it "skips a repository given by URL" do
      expect(manifest.requires.map(&:name)).not_to include("https://github.com/someone/gitonly")
    end
  end

  describe "#dependencies" do
    it "leaves out the compiler and git refs" do
      expect(manifest.dependencies.map(&:name)).to eq(%w(chronos bearssl unittest2 pinned ranged balls))
    end
  end
end
