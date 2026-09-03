# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/uv/sources_table"

RSpec.describe Dependabot::Uv::SourcesTable do
  let(:entry) { 'pkg = { git = "https://example.com/pkg.git", tag = "1.2.3" }' }

  describe ".span" do
    subject(:table) { described_class.span(content)&.last }

    context "when the header is the plain form" do
      let(:content) { "[project]\nname = \"p\"\n\n[tool.uv.sources]\n#{entry}\n" }

      it { is_expected.to include(entry) }
      it { expect(table).not_to include("[project]") }
    end

    # Both of these turned the whole feature off without a word before they were handled
    context "when the file uses CRLF line endings" do
      let(:content) { "[tool.uv.sources]\r\n#{entry}\r\n" }

      it { is_expected.to include("tag = \"1.2.3\"") }
    end

    context "when a comment follows the header" do
      let(:content) { "[tool.uv.sources] # git pins live here\n#{entry}\n" }

      it { is_expected.to include("tag = \"1.2.3\"") }
    end

    context "when the header is indented" do
      let(:content) { "  [tool.uv.sources]\n#{entry}\n" }

      it { is_expected.to include("tag = \"1.2.3\"") }
    end

    context "when another table follows" do
      let(:content) { "[tool.uv.sources]\n#{entry}\n\n[tool.other]\npkg = { tag = \"9.9.9\" }\n" }

      it "stops at that table" do
        expect(table).to include(entry)
        expect(table).not_to include("9.9.9")
      end
    end

    # TOML allows an indented header, so the span has to stop at one too: a `tag` line under
    # another tool's table would otherwise be rewritten as though it were a uv source
    context "when the table that follows is indented" do
      let(:content) { "[tool.uv.sources]\n#{entry}\n\n  [tool.other]\npkg = { tag = \"9.9.9\" }\n" }

      it "stops at that table" do
        expect(table).to include(entry)
        expect(table).not_to include("9.9.9")
      end
    end

    context "when the table runs to the end of the file" do
      let(:content) { "[tool.uv.sources]\n#{entry}" }

      it { is_expected.to include(entry) }
    end

    context "when there is no such table" do
      let(:content) { "[project]\nname = \"p\"\n" }

      it { expect(described_class.span(content)).to be_nil }
    end

    context "when only a sub-table header names it" do
      let(:content) { "[tool.uv.sources.pkg]\ngit = \"https://example.com/pkg.git\"\ntag = \"1.2.3\"\n" }

      # There is no inline entry to rewrite in this form, so there is no table to hand back
      it { expect(described_class.span(content)).to be_nil }
    end

    context "when a table merely starts with the same name" do
      let(:content) { "[tool.uv.sources-extra]\n#{entry}\n" }

      it { expect(described_class.span(content)).to be_nil }
    end
  end

  describe ".tag_regex" do
    it "matches the key on its own line, and not the tail of a longer one carrying the same tag" do
      table = "acme-pkg = { git = \"x\", tag = \"1.2.3\" }\n#{entry}\n"

      expect(table).to match(described_class.tag_regex("pkg", "1.2.3"))
      expect(table[/^acme-pkg.*$/]).not_to match(described_class.tag_regex("pkg", "1.2.3"))
    end

    it "does not match a commented-out entry" do
      expect("# #{entry}\n").not_to match(described_class.tag_regex("pkg", "1.2.3"))
    end

    it "does not match another tag than the one expected" do
      expect(entry).not_to match(described_class.tag_regex("pkg", "9.9.9"))
    end

    # Quoting is the only legal TOML spelling for a name carrying a dot, so both the key and the
    # inner `tag` have to be matched either way
    it "matches a quoted key and a quoted tag" do
      quoted = '"zope.interface" = { "git" = "x", "tag" = "1.2.3" }'

      expect(quoted).to match(described_class.tag_regex("zope.interface", "1.2.3"))
    end

    it "does not match the tail of another key ending in tag" do
      other = 'pkg = { git = "x", other_tag = "1.2.3" }'

      expect(other).not_to match(described_class.tag_regex("pkg", "1.2.3"))
    end

    it "does not cross into a neighbouring entry" do
      neighbours = "pkg = { git = \"x\" }\nother = { git = \"y\", tag = \"1.2.3\" }\n"

      expect(neighbours).not_to match(described_class.tag_regex("pkg", "1.2.3"))
    end
  end

  describe ".writable" do
    subject(:writable) { described_class.writable(content, sources) }

    let(:sources) do
      {
        "pkg" => { url: "https://example.com/pkg.git", ref: "1.2.3" },
        "sub" => { url: "https://example.com/sub.git", ref: "4.5.6" }
      }
    end
    let(:content) do
      "[tool.uv.sources]\n#{entry}\n\n[tool.uv.sources.sub]\ngit = \"https://example.com/sub.git\"\n"
    end

    # `sub` is written as a sub-table, which nothing can rewrite textually
    it { is_expected.to eq("pkg" => { url: "https://example.com/pkg.git", ref: "1.2.3" }) }

    context "when the manifest has no sources table" do
      let(:content) { "[project]\nname = \"p\"\n" }

      it { is_expected.to eq({}) }
    end
  end

  describe ".writable_for" do
    subject(:writable_for) { described_class.writable_for(file) }

    let(:file) { Dependabot::DependencyFile.new(name: "pyproject.toml", content: content) }

    context "with an inline git-and-tag entry" do
      let(:content) { "[tool.uv.sources]\n#{entry}\n" }

      it { is_expected.to eq("pkg" => { url: "https://example.com/pkg.git", ref: "1.2.3" }) }
    end

    # TomlRB is stricter than the tomli the Python helper uses, and this is the first time the Ruby
    # side reads a workspace member manifest, so one it rejects must not fail the job
    context "when the manifest is not valid TOML" do
      let(:content) { "[tool.uv.sources\npkg = {" }

      it { is_expected.to eq({}) }
    end
  end
end
