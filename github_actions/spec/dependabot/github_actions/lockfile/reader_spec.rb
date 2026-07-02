# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/github_actions/lockfile"

RSpec.describe Dependabot::GithubActions::Lockfile::Reader do
  let(:lock_body) { fixture("lockfiles", "actions.lock") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: ".github/workflows/actions.lock",
      content: lock_body
    )
  end

  describe ".from_files" do
    it "returns a reader when a lockfile is present" do
      expect(described_class.from_files([lockfile])).to be_a(described_class)
    end

    it "returns nil when there is no lockfile" do
      other = Dependabot::DependencyFile.new(name: ".github/workflows/ci.yml", content: "on: push")
      expect(described_class.from_files([other])).to be_nil
    end

    it "returns nil when the lockfile is empty" do
      empty = Dependabot::DependencyFile.new(name: ".github/workflows/actions.lock", content: "  \n")
      expect(described_class.from_files([empty])).to be_nil
    end
  end

  describe "#version" do
    subject { described_class.new(lock_body).version }

    it { is_expected.to eq("v0.0.1") }
  end

  describe "#onboarded_paths / #onboarded?" do
    subject(:reader) { described_class.new(lock_body) }

    it "lists the workflows the lock is authoritative for" do
      expect(reader.onboarded_paths).to contain_exactly(
        ".github/workflows/workflow.yml",
        ".github/workflows/unmanaged.yml"
      )
    end

    it "reports onboarded for a listed workflow" do
      expect(reader.onboarded?(".github/workflows/workflow.yml")).to be(true)
    end

    it "reports not onboarded for a workflow absent from the lock" do
      expect(reader.onboarded?(".github/workflows/legacy.yml")).to be(false)
    end
  end

  describe "#pins_action?" do
    subject(:reader) { described_class.new(lock_body) }

    it "is true when the workflow pins the given owner/repo@ref" do
      expect(reader.pins_action?(".github/workflows/workflow.yml", "actions/setup-node@master")).to be(true)
    end

    it "is false for an action the workflow does not pin (a new, un-onboarded action)" do
      expect(reader.pins_action?(".github/workflows/workflow.yml", "actions/checkout@v4")).to be(false)
    end

    it "is scoped per workflow — a pin under another workflow does not count" do
      # checkout@v4 is pinned under unmanaged.yml, not workflow.yml
      expect(reader.pins_action?(".github/workflows/workflow.yml", "actions/checkout@v4")).to be(false)
      expect(reader.pins_action?(".github/workflows/unmanaged.yml", "actions/checkout@v4")).to be(true)
    end

    it "is false for an untracked workflow path" do
      expect(reader.pins_action?(".github/workflows/legacy.yml", "actions/setup-node@master")).to be(false)
    end

    it "is false for an empty action ref" do
      expect(reader.pins_action?(".github/workflows/workflow.yml", "")).to be(false)
    end

    it "matches the ref exactly — a different ref for the same action is not pinned" do
      expect(reader.pins_action?(".github/workflows/workflow.yml", "actions/setup-node@v4")).to be(false)
    end
  end

  describe "invalid YAML" do
    it "raises DependencyFileNotParseable" do
      expect { described_class.new("\tnot: [valid").onboarded_paths }
        .to raise_error(Dependabot::DependencyFileNotParseable)
    end

    it "raises when the lockfile is not a mapping" do
      expect { described_class.new("- just\n- a\n- list").version }
        .to raise_error(Dependabot::DependencyFileNotParseable)
    end
  end

  describe "pin algorithm-prefix validation" do
    it "raises DependencyFileNotParseable on a bare-hex pin (no algo prefix)" do
      bare = <<~LOCK
        version: v0.0.1
        workflows:
          ".github/workflows/ci.yml":
            - "actions/checkout@v4:34e1c0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0"
      LOCK
      expect { described_class.new(bare) }
        .to raise_error(Dependabot::DependencyFileNotParseable, /missing a hash-algorithm prefix/)
    end

    it "accepts a sha256-prefixed pin (forward-compat)" do
      sha256 = <<~LOCK
        version: v0.0.1
        workflows:
          ".github/workflows/ci.yml":
            - "actions/checkout@v4:sha256-abc123"
      LOCK
      expect { described_class.new(sha256) }.not_to raise_error
    end

    it "accepts the sha1-prefixed fixture" do
      expect { described_class.new(lock_body) }.not_to raise_error
    end
  end

  describe "#validate_dependency_entries!" do
    it "passes for the fixture (every entry carries all required keys)" do
      expect { described_class.new(lock_body).validate_dependency_entries! }.not_to raise_error
    end

    it "is a no-op when there is no dependencies section" do
      only_workflows = <<~LOCK
        version: v0.0.1
        workflows:
          ".github/workflows/ci.yml":
            - "actions/checkout@v4:sha1-34e1c0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0"
      LOCK
      expect { described_class.new(only_workflows).validate_dependency_entries! }.not_to raise_error
    end

    %w(branch commit owner_id repo_id).each do |field|
      it "raises DependencyFileNotParseable when an entry is missing #{field}" do
        entry = {
          "branch" => "main",
          "commit" => "sha1-34e1c0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0",
          "owner_id" => 1,
          "repo_id" => 2
        }
        entry.delete(field)
        lock = {
          "version" => "v0.0.1",
          "workflows" => {
            ".github/workflows/ci.yml" => ["actions/checkout@v4:sha1-34e1c0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0"]
          },
          "dependencies" => { "actions/checkout@v4:sha1-34e1c0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0" => entry }
        }
        expect { described_class.new(YAML.dump(lock)).validate_dependency_entries! }
          .to raise_error(Dependabot::DependencyFileNotParseable, /missing required field.*#{field}/)
      end
    end

    it "raises when a dependency entry is not a mapping" do
      lock = <<~LOCK
        version: v0.0.1
        dependencies:
          "actions/checkout@v4:sha1-34e1c0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0": "not a mapping"
      LOCK
      expect { described_class.new(lock).validate_dependency_entries! }
        .to raise_error(Dependabot::DependencyFileNotParseable, /is not a mapping/)
    end
  end
end
