# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/nimble/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Nimble::FileParser do
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "example.nimble",
      content: File.read(File.join(__dir__, "fixtures", "example.nimble"))
    )
  end
  let(:files) { [manifest] }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "example/repo", directory: "/") }
  let(:parser) { described_class.new(dependency_files: files, source: source) }

  it_behaves_like "a dependency file parser" do
    let(:dependencies) { parser.parse }
  end

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "returns the packages, not the compiler or git refs" do
      expect(dependencies.map(&:name)).to eq(%w(chronos bearssl unittest2 pinned ranged balls))
    end

    it "takes the version a requirement starts from" do
      versions = dependencies.to_h { |dependency| [dependency.name, dependency.version] }
      expect(versions).to eq(
        "chronos" => "4.0.4",
        "bearssl" => nil,
        "unittest2" => "0.2.0",
        "pinned" => "1.2.3",
        "ranged" => "1.0",
        "balls" => "5.0"
      )
    end

    it "keeps the requirement, file and group of each package" do
      chronos = dependencies.find { |dependency| dependency.name == "chronos" }
      expect(chronos.requirements).to eq(
        [{ requirement: ">= 4.0.4", file: "example.nimble", groups: ["dependencies"], source: nil }]
      )
    end

    it "keeps no requirement for a package without a version" do
      bearssl = dependencies.find { |dependency| dependency.name == "bearssl" }
      expect(bearssl.requirements.first[:requirement]).to be_nil
    end

    it "puts a task's packages in the group of the task" do
      balls = dependencies.find { |dependency| dependency.name == "balls" }
      expect(balls.requirements.first[:groups]).to eq(["test"])
    end

    it "uses the nimble package manager" do
      expect(dependencies.map(&:package_manager).uniq).to eq(["nimble"])
    end

    context "when a package is required twice" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "example.nimble",
          content: %(requires "foo >= 1.0"\ntaskRequires "test", "foo >= 1.0"\n)
        )
      end

      it "returns one dependency with both requirements" do
        expect(dependencies.length).to eq(1)
        expect(dependencies.first.requirements.map { |requirement| requirement[:groups] })
          .to eq([["dependencies"], ["test"]])
        expect(dependencies.first.version).to eq("1.0")
      end
    end

    context "when the requirements start from different versions" do
      let(:manifest) do
        Dependabot::DependencyFile.new(
          name: "example.nimble",
          content: %(requires "foo >= 1.0"\ntaskRequires "test", "foo >= 1.2"\n)
        )
      end

      it "has no single current version" do
        expect(dependencies.first.version).to be_nil
      end
    end

    context "without a package file" do
      let(:files) { [] }

      it "raises DependencyFileNotFound" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
