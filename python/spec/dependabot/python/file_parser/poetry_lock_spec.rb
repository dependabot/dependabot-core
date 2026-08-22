# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/poetry_lock"

RSpec.describe Dependabot::Python::FileParser::PoetryLock do
  subject(:lock) { described_class.from_file(file) }

  let(:file) do
    Dependabot::DependencyFile.new(
      name: "poetry.lock",
      content: content
    )
  end
  let(:content) do
    <<~TOML
      [[package]]
      name = "requests"
      version = "2.32.0"

      [[package]]
      name = "local"
      version = "1.0.0"

      [package.source]
      type = "directory"
    TOML
  end

  it "parses packages and source types" do
    expect(lock.packages.map(&:to_h)).to eq(
      [
        { name: "requests", version: "2.32.0", source_type: nil },
        { name: "local", version: "1.0.0", source_type: "directory" }
      ]
    )
  end

  it "finds a package version by normalized name" do
    expect(lock.version_for("Requests", &:downcase)).to eq("2.32.0")
  end

  context "with no packages" do
    let(:content) { "lock-version = \"2.0\"\n" }

    it "returns an empty package list" do
      expect(lock.packages).to eq([])
    end
  end

  context "with a malformed package" do
    let(:content) do
      <<~TOML
        [[package]]
        name = "requests"
        version = 2
      TOML
    end

    it "raises an explicit type error" do
      expect { lock }.to raise_error(TypeError, "Poetry lock package version must be a string")
    end
  end
end
