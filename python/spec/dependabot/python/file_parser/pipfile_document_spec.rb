# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/pipfile_document"

RSpec.describe Dependabot::Python::FileParser::PipfileDocument do
  subject(:document) { described_class.from_file(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "Pipfile", content: content) }
  let(:content) do
    <<~TOML
      [packages]
      String_Pin = "  ==1  "
      Table_Pin = { version = "  ==2  " }
      empty_string = ""
      empty_table = { version = "" }
      git = { version = true, git = false }
      path = { version = "==3", path = false }
      disabled = { version = false }
    TOML
  end

  it "retains names, input forms, and whitespace" do
    entries = document.entries("packages")
    expect(entries.map(&:name)).to eq(%w(String_Pin Table_Pin empty_string empty_table git path disabled))
    expect(entries.take(4).map(&:lookup_version)).to eq(["==1", "  ==2  ", "", ""])
    expect(entries.take(4).map(&:requirement)).to eq(["  ==1  ", "  ==2  ", "*", ""])
  end

  it "distinguishes version presence from source exclusion" do
    entries = document.entries("packages")
    expect(entries.map(&:specifies_version?)).to eq([true, true, true, true, true, true, false])
    expect(entries.map(&:git_or_path?)).to eq([false, false, false, false, true, true, false])
  end

  context "with a numeric version" do
    let(:content) { "[packages]\nlocal = { version = 123, path = false }\n" }

    it "rejects the version shape at the existing presence check" do
      expect { document.entries("packages").first.specifies_version? }
        .to raise_error(TypeError, /Pipfile.*version/)
    end
  end

  context "with an empty array section" do
    let(:content) { "packages = []" }

    it "retains the empty section result" do
      expect(document.entries("packages")).to eq([])
    end
  end

  context "with invalid TOML" do
    let(:content) { "[invalid" }

    it "reports the file path" do
      expect { document }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
        expect(error.file_name).to eq("Pipfile")
      end
    end
  end
end
