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

  describe "targeted lock queries" do
    subject(:document) { described_class.from_content(content) }

    let(:content) do
      <<~TOML
        [[package]]
        name = "unrelated"
        version = false
        source = false

        [[package]]
        name = "Requests"
        version = "2.32.0"
        optional = true
        groups = "dev"
        markers = { dev = 'python_version < "3.13"' }

        [package.source]
        type = "git"
        url = "https://example.com/requests.git"
        reference = "v2.32.0"
        resolved_reference = "commit-sha"
        subdirectory = "python"

        [metadata]
        python-versions = ">=3.10"
        content-hash = "original-hash"
      TOML
    end

    it "reads the selected source without decoding unrelated packages" do
      record = document.record_for("requests", &:downcase)

      expect(record.version).to eq("2.32.0")
      expect(record.git_source).to have_attributes(
        url: "https://example.com/requests.git",
        reference: "v2.32.0",
        subdirectory: "python"
      )
    end

    it "retains legacy group handling and group-specific markers" do
      scope = document.records_for("requests", &:downcase).first.scope

      expect(scope.optional).to be(true)
      expect(scope.groups).to eq(["dev"])
      expect(scope.markers_for("dev")).to eq(['(python_version < "3.13")'])
    end

    it "reads lock metadata independently of packages" do
      expect(document.python_versions).to eq(">=3.10")
      expect(document.content_hash).to eq("original-hash")
    end

    context "with malformed unused metadata" do
      let(:content) { super().sub('content-hash = "original-hash"', "content-hash = false") }

      it "reports the field only when consumed" do
        expect(document.record_for("requests", &:downcase).version).to eq("2.32.0")
        expect { document.content_hash }.to raise_error(TypeError, /metadata.*content-hash/)
      end
    end

    context "without recorded groups or markers" do
      let(:content) { super().gsub(/^(?:groups|markers) = .*\n/, "") }

      it "keeps the legacy main-install scope" do
        scope = document.records_for("requests", &:downcase).first.scope

        expect(scope.groups).to eq(["main"])
        expect(scope.markers_for("main")).to eq([])
      end
    end
  end
end
