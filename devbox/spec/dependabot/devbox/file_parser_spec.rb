# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers"
require "dependabot/devbox/file_parser"

RSpec.describe Dependabot::Devbox::FileParser do
  let(:parser) do
    described_class.new(dependency_files: files, source: source)
  end
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "test/repo", directory: "/")
  end

  it "is registered for the devbox package manager" do
    expect(Dependabot::FileParsers.for_package_manager("devbox")).to eq(described_class)
  end

  context "with the basic project (all three constraint shapes)" do
    let(:files) { project_dependency_files("devbox/basic") }

    it "returns one dependency per package, sorted by name" do
      expect(parser.parse.map(&:name)).to eq(%w(go python ripgrep))
    end

    it "extracts the constraint from each entry" do
      requirements = parser.parse.to_h { |d| [d.name, d.requirements.first[:requirement]] }
      expect(requirements).to eq(
        "ripgrep" => "latest",
        "python" => "3.10",
        "go" => "1.21.5"
      )
    end

    it "reads the resolved version from the lockfile" do
      versions = parser.parse.to_h { |d| [d.name, d.version] }
      expect(versions).to eq(
        "ripgrep" => "14.1.0",
        "python" => "3.10.13",
        "go" => "1.21.5"
      )
    end

    it "records the nixhub source and the manifest file" do
      req = parser.parse.find { |d| d.name == "python" }.requirements.first
      expect(req).to include(
        file: "devbox.json",
        groups: [],
        source: { type: "nixhub" }
      )
    end
  end

  context "with inline manifest content" do
    let(:files) { [manifest, lockfile].compact }
    let(:lockfile) { nil }
    let(:manifest) do
      Dependabot::DependencyFile.new(name: "devbox.json", content: manifest_content)
    end

    context "when an entry has no constraint" do
      let(:manifest_content) { '{ "packages": ["ripgrep"] }' }

      it "defaults the constraint to latest" do
        dep = parser.parse.first
        expect(dep.name).to eq("ripgrep")
        expect(dep.requirements.first[:requirement]).to eq("latest")
      end
    end

    context "when an entry is a future scoped name" do
      let(:manifest_content) { '{ "packages": ["@acme/tool@1.2.3"] }' }

      it "splits on the last @" do
        dep = parser.parse.first
        expect(dep.name).to eq("@acme/tool")
        expect(dep.requirements.first[:requirement]).to eq("1.2.3")
      end
    end

    context "with JWCC comments and trailing commas" do
      let(:manifest_content) do
        <<~JSONC
          {
            // packages tracked by devbox
            "packages": [
              "python@3.10", /* pinned minor */
              "ripgrep@latest",
            ],
          }
        JSONC
      end

      it "parses the packages despite the comments" do
        expect(parser.parse.map(&:name)).to eq(%w(python ripgrep))
      end
    end

    context "without a lockfile" do
      let(:manifest_content) { '{ "packages": ["python@3.10"] }' }

      it "leaves the resolved version nil" do
        expect(parser.parse.first.version).to be_nil
      end
    end

    context "when the packages field is absent" do
      let(:manifest_content) { '{ "shell": {} }' }

      it "returns no dependencies" do
        expect(parser.parse).to be_empty
      end
    end
  end
end
