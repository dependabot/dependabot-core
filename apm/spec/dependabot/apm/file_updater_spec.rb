# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/apm/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Apm::FileUpdater do
  let(:manifest_body) do
    <<~YAML
      dependencies:
        apm:
          - microsoft/edge-ai#v1.0.0
          - microsoft/edge-ai-extras#v1.0.0
    YAML
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "apm.yml", content: manifest_body)
  end
  let(:declaration_span) { "2:6:2:30" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "microsoft/edge-ai",
      version: "1.2.0",
      previous_version: "1.0.0",
      requirements: [{
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/edge-ai",
          ref: "v1.2.0",
          branch: nil
        },
        metadata: { declaration_string: "microsoft/edge-ai#v1.0.0", declaration_span: declaration_span }
      }],
      previous_requirements: [{
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/edge-ai",
          ref: "v1.0.0",
          branch: nil
        },
        metadata: { declaration_string: "microsoft/edge-ai#v1.0.0", declaration_span: declaration_span }
      }],
      package_manager: "apm"
    )
  end
  let(:updater) do
    described_class.new(
      dependency_files: [manifest],
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  it_behaves_like "a dependency file updater"

  describe ".updated_files_regex" do
    it "matches apm.yml" do
      expect(described_class.updated_files_regex).to all(be_a(Regexp))
      expect(described_class.updated_files_regex.any? { |re| "apm.yml".match?(re) }).to be(true)
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns a single updated manifest" do
      expect(updated_files.length).to eq(1)
      expect(updated_files.first.name).to eq("apm.yml")
    end

    it "bumps the pinned ref" do
      expect(updated_files.first.content).to include("microsoft/edge-ai#v1.2.0")
    end

    it "does not touch an entry that merely shares the same prefix" do
      expect(updated_files.first.content).to include("microsoft/edge-ai-extras#v1.0.0")
    end

    context "when the manifest quotes the entry" do
      let(:manifest_body) do
        <<~YAML
          dependencies:
            apm:
              - "microsoft/edge-ai#v1.0.0"
        YAML
      end
      let(:declaration_span) { "2:6:2:32" }

      it "still bumps the pinned ref and keeps the quotes" do
        expect(updated_files.first.content).to include("\"microsoft/edge-ai#v1.2.0\"")
      end
    end

    context "when the manifest uses a flow sequence" do
      let(:manifest_body) do
        <<~YAML
          dependencies: { apm: ["microsoft/edge-ai#v1.0.0"] }
        YAML
      end
      let(:declaration_span) { "0:22:0:48" }

      it "bumps the pinned ref inside the flow sequence" do
        expect(updated_files.first.content)
          .to include("dependencies: { apm: [\"microsoft/edge-ai#v1.2.0\"] }")
      end
    end

    context "when the same text appears elsewhere in the manifest" do
      let(:manifest_body) do
        <<~YAML
          # keep microsoft/edge-ai#v1.0.0 until the audit clears
          dependencies:
            apm:
              - microsoft/edge-ai#v1.0.0
          notes:
            reference: microsoft/edge-ai#v1.0.0
        YAML
      end
      let(:declaration_span) { "3:6:3:30" }

      it "rewrites only the real dependency entry" do
        content = updated_files.first.content
        expect(content).to include("    - microsoft/edge-ai#v1.2.0")
        expect(content).to include("# keep microsoft/edge-ai#v1.0.0 until the audit clears")
        expect(content).to include("reference: microsoft/edge-ai#v1.0.0")
      end
    end

    context "when nothing changed" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "microsoft/edge-ai",
          version: "1.0.0",
          previous_version: "1.0.0",
          requirements: [{
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/microsoft/edge-ai",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "microsoft/edge-ai#v1.0.0" }
          }],
          previous_requirements: [{
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/microsoft/edge-ai",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "microsoft/edge-ai#v1.0.0" }
          }],
          package_manager: "apm"
        )
      end

      it "raises because no files were changed" do
        expect { updated_files }.to raise_error("No files changed!")
      end
    end
  end
end
