# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/update_checker/requirements_updater"
require "dependabot/swift/version"

RSpec.describe Dependabot::Swift::UpdateChecker::RequirementsUpdater do
  let(:requirements) do
    [{
      file: "MyApp.xcodeproj/project.pbxproj",
      requirement: ">= 7.0.0, < 8.0.0",
      groups: [],
      source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
      metadata: { kind: "upToNextMajorVersion", requirement_string: "from: \"7.0.0\"" }
    }]
  end

  let(:target_version) { "7.0.2" }
  let(:xcode_mode) { true }
  let(:target_commit_sha) { nil }

  let(:updater) do
    described_class.new(
      requirements: requirements,
      target_version: target_version,
      xcode_mode: xcode_mode,
      target_commit_sha: target_commit_sha
    )
  end

  describe "#initialize" do
    it "stores target_commit_sha" do
      updater_with_sha = described_class.new(
        requirements: requirements,
        target_version: target_version,
        xcode_mode: true,
        target_commit_sha: "abc123def456"
      )
      expect(updater_with_sha.send(:target_commit_sha)).to eq("abc123def456")
    end

    it "handles nil target_commit_sha" do
      expect(updater.send(:target_commit_sha)).to be_nil
    end
  end

  describe "#updated_requirements" do
    context "in xcode_mode" do
      let(:xcode_mode) { true }

      it "updates the requirement string" do
        updated = updater.updated_requirements
        expect(updated.first[:requirement]).to eq(">= 7.0.2, < 8.0.0")
      end

      it "updates the metadata requirement_string" do
        updated = updater.updated_requirements
        expect(updated.first[:metadata][:requirement_string]).to eq("from: \"7.0.2\"")
      end
    end
  end

  describe "#update_source_ref" do
    context "when target_commit_sha is provided" do
      let(:target_commit_sha) { "91132c0fe9a98e76f3d7381a608685aa41770706" }

      it "uses the commit SHA for the ref" do
        updated = updater.updated_requirements
        expect(updated.first[:source][:ref]).to eq("91132c0fe9a98e76f3d7381a608685aa41770706")
      end
    end

    context "when target_commit_sha is nil" do
      let(:target_commit_sha) { nil }

      it "falls back to version string for the ref" do
        updated = updater.updated_requirements
        expect(updated.first[:source][:ref]).to eq("7.0.2")
      end
    end

    context "when source is nil" do
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: ">= 7.0.0, < 8.0.0",
          groups: [],
          source: nil,
          metadata: { kind: "upToNextMajorVersion", requirement_string: "from: \"7.0.0\"" }
        }]
      end

      it "returns nil source unchanged" do
        updated = updater.updated_requirements
        expect(updated.first[:source]).to be_nil
      end
    end
  end

  describe "xcode requirement kinds" do
    context "with exactVersion" do
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: "= 7.0.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: { kind: "exactVersion", requirement_string: "exact: \"7.0.0\"" }
        }]
      end

      it "updates to exact new version" do
        updated = updater.updated_requirements
        expect(updated.first[:requirement]).to eq("= 7.0.2")
        expect(updated.first[:metadata][:requirement_string]).to eq("exact: \"7.0.2\"")
      end
    end

    context "with upToNextMinorVersion" do
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: ">= 7.0.0, < 7.1.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: { kind: "upToNextMinorVersion", requirement_string: ".upToNextMinor(from: \"7.0.0\")" }
        }]
      end

      it "updates to new minor range" do
        updated = updater.updated_requirements
        expect(updated.first[:requirement]).to eq(">= 7.0.2, < 7.1.0")
        expect(updated.first[:metadata][:requirement_string]).to eq(".upToNextMinor(from: \"7.0.2\")")
      end
    end

    context "with versionRange" do
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: ">= 7.0.0, < 8.0.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: { kind: "versionRange", requirement_string: "\"7.0.0\"..<\"8.0.0\"" }
        }]
      end

      it "updates min version while preserving max" do
        updated = updater.updated_requirements
        expect(updated.first[:requirement]).to eq(">= 7.0.2, < 8.0.0")
        expect(updated.first[:metadata][:requirement_string]).to eq("\"7.0.2\"..<\"8.0.0\"")
      end
    end
  end
end
