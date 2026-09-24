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
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency_files) { [manifest] }

  it_behaves_like "a dependency file updater"

  describe ".updated_files_regex" do
    it "matches apm.yml" do
      expect(described_class.updated_files_regex).to all(be_a(Regexp))
      expect(described_class.updated_files_regex.any? { |re| "apm.yml".match?(re) }).to be(true)
    end

    it "matches apm.lock.yaml" do
      expect(described_class.updated_files_regex.any? { |re| "apm.lock.yaml".match?(re) }).to be(true)
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

    context "when a duplicated entry shares a line and the bumped ref is longer" do
      let(:manifest_body) do
        <<~YAML
          dependencies: { apm: ["acme/widgets#v1.9.0", "acme/widgets#v1.9.0"] }
        YAML
      end
      let(:dependency) do
        requirement = lambda do |ref, span|
          {
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/acme/widgets", ref: ref, branch: nil },
            metadata: { declaration_string: "acme/widgets#v1.9.0", declaration_span: span }
          }
        end

        Dependabot::Dependency.new(
          name: "acme/widgets",
          version: "1.10.0",
          previous_version: "1.9.0",
          requirements: [requirement.call("v1.10.0", "0:22:0:43"), requirement.call("v1.10.0", "0:45:0:66")],
          previous_requirements: [requirement.call("v1.9.0", "0:22:0:43"), requirement.call("v1.9.0", "0:45:0:66")],
          package_manager: "apm"
        )
      end

      it "updates both occurrences even though the earlier edit shifts later offsets" do
        expect(updated_files.first.content)
          .to eq(%(dependencies: { apm: ["acme/widgets#v1.10.0", "acme/widgets#v1.10.0"] }\n))
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

    context "when a lockfile is present" do
      subject(:updated_lockfile) { updated_files.find { |f| f.name == "apm.lock.yaml" } }

      let(:lockfile_body) do
        <<~YAML
          apm_version: "0.4.2"
          packages:
            - name: microsoft/edge-ai
              source: github.com/microsoft/edge-ai
              ref: v1.0.0
              resolved: 0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e
              integrity: sha256-0000000000000000000000000000000000000000000=
            - name: microsoft/edge-ai-extras
              source: github.com/microsoft/edge-ai-extras
              ref: v1.0.0
              resolved: 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b
              integrity: sha256-1111111111111111111111111111111111111111111=
        YAML
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(name: "apm.lock.yaml", content: lockfile_body)
      end
      let(:dependency_files) { [manifest, lockfile] }

      it "returns both the updated manifest and lockfile" do
        expect(updated_files.map(&:name)).to contain_exactly("apm.yml", "apm.lock.yaml")
      end

      it "bumps the matching package's ref to the manifest ref" do
        expect(updated_lockfile.content)
          .to match(%r{- name: microsoft/edge-ai\n\s+source:[^\n]+\n\s+ref: v1\.2\.0\n})
      end

      it "leaves resolved and integrity for `apm install --update` to regenerate" do
        expect(updated_lockfile.content).to include("resolved: 0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e")
        expect(updated_lockfile.content).to include("integrity: sha256-0000000000000000000000000000000000000000000=")
      end

      it "does not touch an unrelated package that shares a name prefix" do
        expect(updated_lockfile.content)
          .to match(%r{- name: microsoft/edge-ai-extras\n\s+source:[^\n]+\n\s+ref: v1\.0\.0\n})
      end

      context "when the bumped dependency is absent from the lockfile" do
        let(:lockfile_body) do
          <<~YAML
            apm_version: "0.4.2"
            packages:
              - name: octo-org/octo-skills
                source: github.com/octo-org/octo-skills
                ref: v2.3.1
                resolved: 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b
                integrity: sha256-1111111111111111111111111111111111111111111=
          YAML
        end

        it "returns only the updated manifest" do
          expect(updated_files.map(&:name)).to contain_exactly("apm.yml")
        end
      end
    end
  end
end
