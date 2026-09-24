# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/apm/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Apm::FileParser do
  subject(:parser) do
    described_class.new(dependency_files: files, source: source)
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/agent-repo",
      directory: "/"
    )
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "apm.yml",
      content: fixture("manifests", "apm.yml")
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "apm.lock.yaml",
      content: fixture("manifests", "apm.lock.yaml")
    )
  end
  let(:files) { [manifest, lockfile] }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "only parses the supported string-shorthand git entries pinned to a semver tag" do
      expect(dependencies.map(&:name)).to contain_exactly(
        "microsoft/edge-ai",
        "octo-org/octo-skills",
        "gitlab.com/acme/prompts",
        "qa-org/qa-helpers"
      )
    end

    describe "a GitHub production dependency pinned to a tag" do
      subject(:dependency) { dependencies.find { |d| d.name == "microsoft/edge-ai" } }

      it "has the normalised version and git source" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.version).to eq("1.0.0")
        expect(dependency.production?).to be(true)
        expect(dependency.requirements).to eq(
          [{
            requirement: nil,
            file: "apm.yml",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/microsoft/edge-ai",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: {
              declaration_string: "microsoft/edge-ai#v1.0.0",
              declaration_line: "4"
            }
          }]
        )
      end
    end

    describe "a dependency hosted on a non-default host" do
      subject(:dependency) { dependencies.find { |d| d.name == "gitlab.com/acme/prompts" } }

      it "keeps the full host in the git URL" do
        expect(dependency.version).to eq("0.5.0")
        expect(dependency.requirements.first[:source][:url])
          .to eq("https://gitlab.com/acme/prompts")
        expect(dependency.requirements.first[:source][:ref]).to eq("v0.5.0")
      end
    end

    describe "a dependency pinned to a branch rather than a semver tag" do
      it "is excluded because it cannot be version-bumped" do
        expect(dependencies.map(&:name)).not_to include("big-corp/pinned-branch")
      end
    end

    describe "a devDependencies entry" do
      subject(:dependency) { dependencies.find { |d| d.name == "qa-org/qa-helpers" } }

      it "is marked as a development dependency" do
        expect(dependency.version).to eq("3.1.4")
        expect(dependency.requirements.first[:groups]).to eq(["development"])
        expect(dependency.production?).to be(false)
      end
    end

    context "when the manifest has a syntax error" do
      let(:manifest) do
        Dependabot::DependencyFile.new(name: "apm.yml", content: "dependencies: [:")
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "when the manifest has no apm dependency blocks" do
      let(:manifest) do
        Dependabot::DependencyFile.new(name: "apm.yml", content: "default_host: github.com\n")
      end

      it { is_expected.to eq([]) }
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    it "has the correct name" do
      expect(ecosystem.name).to eq("apm")
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "reads the apm version from the lockfile" do
        expect(package_manager.name).to eq("apm")
        expect(package_manager.version.to_s).to eq("0.4.2")
      end

      context "without a lockfile" do
        let(:files) { [manifest] }

        it "falls back to the default version" do
          expect(package_manager.version.to_s).to eq("0.0.0")
        end
      end
    end
  end
end
