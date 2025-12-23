# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/lean/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Lean::FileParser do
  let(:files) { [lean_toolchain] }
  let(:lean_toolchain) do
    Dependabot::DependencyFile.new(
      name: "lean-toolchain",
      content: lean_toolchain_content
    )
  end
  let(:lean_toolchain_content) { "leanprover/lean4:v4.26.0\n" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with a valid lean-toolchain file" do
      let(:lean_toolchain_content) { "leanprover/lean4:v4.26.0\n" }

      it "parses a single dependency" do
        expect(dependencies.length).to eq(1)
      end

      it "has the correct name" do
        expect(dependencies.first.name).to eq("lean4")
      end

      it "has the correct version" do
        expect(dependencies.first.version).to eq("4.26.0")
      end

      it "has the correct requirements" do
        expect(dependencies.first.requirements).to eq(
          [{
            requirement: "4.26.0",
            file: "lean-toolchain",
            groups: [],
            source: { type: "default" }
          }]
        )
      end
    end

    context "with an RC version" do
      let(:lean_toolchain_content) { "leanprover/lean4:v4.27.0-rc2\n" }

      it "parses the RC version correctly" do
        expect(dependencies.first.version).to eq("4.27.0-rc2")
      end
    end

    context "with whitespace" do
      let(:lean_toolchain_content) { "  leanprover/lean4:v4.26.0  \n" }

      it "strips whitespace and parses correctly" do
        expect(dependencies.first.version).to eq("4.26.0")
      end
    end

    context "with an invalid format" do
      let(:lean_toolchain_content) { "invalid-format\n" }

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end

    context "with an empty file" do
      let(:lean_toolchain_content) { "" }

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end

    context "with both toolchain and lake-manifest.json" do
      let(:files) { [lean_toolchain, lake_manifest] }
      let(:lean_toolchain_content) { "leanprover/lean4:v4.26.0\n" }
      let(:lake_manifest) do
        Dependabot::DependencyFile.new(
          name: "lake-manifest.json",
          content: fixture("projects", "lake_project", "lake-manifest.json")
        )
      end

      it "parses both toolchain and Lake dependencies" do
        expect(dependencies.length).to eq(3) # lean4 + batteries + aesop
      end

      it "includes the lean4 toolchain dependency" do
        lean4 = dependencies.find { |d| d.name == "lean4" }
        expect(lean4).not_to be_nil
        expect(lean4.version).to eq("4.26.0")
      end

      it "includes the batteries Lake package" do
        batteries = dependencies.find { |d| d.name == "batteries" }
        expect(batteries).not_to be_nil
        expect(batteries.version).to eq("dff865b7ee7011518d59abfc101c368293173150")
      end

      it "includes the aesop Lake package" do
        aesop = dependencies.find { |d| d.name == "aesop" }
        expect(aesop).not_to be_nil
        expect(aesop.version).to eq("fa78cf032194308a950a264ed87b422a2a7c1c6c")
      end

      it "sets correct source info for Lake packages" do
        batteries = dependencies.find { |d| d.name == "batteries" }
        req = batteries.requirements.first

        expect(req[:source][:type]).to eq("git")
        expect(req[:source][:url]).to eq("https://github.com/leanprover-community/batteries")
      end
    end

    context "with only lake-manifest.json (no toolchain)" do
      let(:files) { [lake_manifest] }
      let(:lake_manifest) do
        Dependabot::DependencyFile.new(
          name: "lake-manifest.json",
          content: fixture("projects", "lake_project", "lake-manifest.json")
        )
      end

      it "parses Lake dependencies only" do
        expect(dependencies.length).to eq(2)
        expect(dependencies.map(&:name)).to contain_exactly("batteries", "aesop")
      end
    end
  end
end
