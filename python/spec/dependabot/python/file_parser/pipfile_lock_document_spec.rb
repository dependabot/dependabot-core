# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/pipfile_lock_document"

RSpec.describe Dependabot::Python::FileParser::PipfileLockDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "Pipfile.lock", content: data.to_json) }
  let(:data) do
    {
      "default" => {
        "String_Pin" => "  ==1  ",
        "table" => { "version" => "  ==2  " },
        "path" => { "version" => 123, "path" => nil },
        "ignored" => [false]
      },
      "develop" => false
    }
  end

  it "preserves stored names and tolerant enumeration" do
    entries = document.entries("default")
    expect(entries.map(&:name)).to eq(%w(String_Pin table path))
    expect(entries.map(&:lockfile_version)).to eq(["  ==1  ", "  ==2  ", nil])
    expect(document.entries("develop")).to eq([])
  end

  it "strips lookup strings without normalizing stored keys or table versions" do
    expect(document.version_for("default", "String_Pin")).to eq("==1")
    expect(document.version_for("default", "string-pin")).to be_nil
    expect(document.version_for("default", "table")).to eq("  ==2  ")
    expect(document.version_for("default", "ignored")).to be_nil
    expect(document.version_for("develop", "anything")).to be_nil
  end

  context "with a scalar entry" do
    let(:data) { { "default" => { "bad" => false } } }

    it "keeps enumeration skips distinct from lookup failures" do
      expect(document.entries("default")).to eq([])
      expect { document.version_for("default", "bad") }.to raise_error(TypeError, /Pipfile.lock.*entry/)
    end
  end

  context "with invalid JSON" do
    let(:file) { Dependabot::DependencyFile.new(name: "Pipfile.lock", content: "{ invalid") }

    it "reports the file path" do
      expect { document }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
        expect(error.file_name).to eq("Pipfile.lock")
      end
    end
  end
end
