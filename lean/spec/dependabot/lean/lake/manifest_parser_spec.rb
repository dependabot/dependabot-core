# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/lean/lake/manifest_parser"

RSpec.describe Dependabot::Lean::Lake::ManifestParser do
  let(:parser) { described_class.new(manifest_file: manifest_file) }

  describe "#parse" do
    context "with a valid lake-manifest.json" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "lake-manifest.json",
          content: fixture("projects", "lake_project", "lake-manifest.json")
        )
      end

      it "returns the correct number of dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(2)
      end

      it "parses the batteries dependency correctly" do
        deps = parser.parse
        batteries = deps.find { |d| d.name == "batteries" }

        expect(batteries).not_to be_nil
        expect(batteries.version).to eq("dff865b7ee7011518d59abfc101c368293173150")
        expect(batteries.package_manager).to eq("lean")
      end

      it "sets the correct source information" do
        deps = parser.parse
        batteries = deps.find { |d| d.name == "batteries" }

        expect(batteries.requirements.length).to eq(1)
        req = batteries.requirements.first

        expect(req[:file]).to eq("lake-manifest.json")
        expect(req[:source][:type]).to eq("git")
        expect(req[:source][:url]).to eq("https://github.com/leanprover-community/batteries")
        expect(req[:source][:ref]).to eq("main")
        expect(req[:source][:branch]).to eq("main")
      end

      it "parses the aesop dependency correctly" do
        deps = parser.parse
        aesop = deps.find { |d| d.name == "aesop" }

        expect(aesop).not_to be_nil
        expect(aesop.version).to eq("fa78cf032194308a950a264ed87b422a2a7c1c6c")

        req = aesop.requirements.first
        expect(req[:source][:ref]).to eq("master")
      end
    end

    context "with an empty packages array" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "lake-manifest.json",
          content: '{"version": "1.1.0", "packages": []}'
        )
      end

      it "returns an empty array" do
        expect(parser.parse).to eq([])
      end
    end

    context "with invalid JSON" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "lake-manifest.json",
          content: "not valid json"
        )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with a non-git package type" do
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "lake-manifest.json",
          content: <<~JSON
            {
              "version": "1.1.0",
              "packages": [
                {
                  "type": "path",
                  "name": "local-package",
                  "dir": "./local"
                }
              ]
            }
          JSON
        )
      end

      it "skips non-git packages" do
        expect(parser.parse).to eq([])
      end
    end
  end
end
