# typed: true
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
        { name: "requests", version: "2.32.0", source_type: nil, optional: false, markers: nil },
        { name: "local", version: "1.0.0", source_type: "directory", optional: false, markers: nil }
      ]
    )
  end

  it "finds a package version by normalized name" do
    expect(lock.version_for("Requests", &:downcase)).to eq("2.32.0")
  end

  context "with an optional, extra-scoped package" do
    let(:content) do
      <<~TOML
        [[package]]
        name = "certifi"
        version = "2024.2.2"
        optional = true
        markers = "extra == \\"security\\""
      TOML
    end

    it "parses the optional and markers fields" do
      certifi = lock.packages.first

      expect(certifi.optional).to be(true)
      expect(certifi.markers).to eq("extra == \"security\"")
    end
  end

  context "with a group-keyed marker table (poetry.lock format 2.1+)" do
    let(:content) do
      <<~TOML
        [[package]]
        name = "exceptiongroup"
        version = "1.3.1"
        optional = true
        markers = {main = "extra == \\"security\\" and python_version < \\"3.11\\"", dev = "python_version < \\"3.11\\""}
      TOML
    end

    it "parses each group's marker string instead of raising" do
      exceptiongroup = lock.packages.first

      expect(exceptiongroup.markers).to eq(
        "main" => "extra == \"security\" and python_version < \"3.11\"",
        "dev" => "python_version < \"3.11\""
      )
      expect(exceptiongroup.marker_strings).to contain_exactly(
        "extra == \"security\" and python_version < \"3.11\"",
        "python_version < \"3.11\""
      )
    end
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
