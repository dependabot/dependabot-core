# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/job/blocked_version"
require "dependabot/updater/blocked_version_detector"
require "support/dummy_package_manager/dummy"

RSpec.describe Dependabot::Updater::BlockedVersionDetector do
  subject(:detector) do
    described_class.new(
      package_manager: "dummy",
      blocked_versions: blocked_versions,
      previous_dependencies: previous_dependencies,
      current_dependencies: current_dependencies
    )
  end

  let(:blocked_versions) { [] }
  let(:previous_dependencies) { [] }
  let(:current_dependencies) { [] }

  def transitive_dependency(name:, version:)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      requirements: [],
      package_manager: "dummy"
    )
  end

  def direct_dependency(name:, version:)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      requirements: [{ file: "manifest", requirement: "= #{version}", groups: [], source: nil }],
      package_manager: "dummy"
    )
  end

  def blocked_version(name:, requirement:, reason: nil)
    Dependabot::Job::BlockedVersion.from_hash(
      {
        "dependency-name" => name,
        "version-requirement" => requirement,
        "reason" => reason
      }.compact
    )
  end

  describe "#transitive_changes" do
    context "when no dependencies changed" do
      let(:previous_dependencies) { [transitive_dependency(name: "left-pad", version: "1.0.0")] }
      let(:current_dependencies) { [transitive_dependency(name: "left-pad", version: "1.0.0")] }

      it "returns no changes" do
        expect(detector.transitive_changes).to be_empty
      end
    end

    context "when a transitive dependency version changed" do
      let(:previous_dependencies) { [transitive_dependency(name: "left-pad", version: "1.0.0")] }
      let(:current_dependencies) { [transitive_dependency(name: "left-pad", version: "1.1.0")] }

      it "reports the change with previous and new versions" do
        change = detector.transitive_changes.first

        expect(detector.transitive_changes.size).to eq(1)
        expect(change.name).to eq("left-pad")
        expect(change.previous_version).to eq("1.0.0")
        expect(change.new_version).to eq("1.1.0")
        expect(change).not_to be_blocked
      end
    end

    context "when a transitive dependency is newly introduced" do
      let(:previous_dependencies) { [] }
      let(:current_dependencies) { [transitive_dependency(name: "left-pad", version: "1.1.0")] }

      it "reports the change with no previous version" do
        change = detector.transitive_changes.first

        expect(change.name).to eq("left-pad")
        expect(change.previous_version).to be_nil
        expect(change.new_version).to eq("1.1.0")
      end
    end

    context "when a top-level dependency changed" do
      let(:previous_dependencies) { [direct_dependency(name: "rails", version: "7.0.0")] }
      let(:current_dependencies) { [direct_dependency(name: "rails", version: "7.1.0")] }

      it "does not report direct dependencies as transitive changes" do
        expect(detector.transitive_changes).to be_empty
      end
    end

    context "when a transitive dependency has no version" do
      let(:current_dependencies) do
        [Dependabot::Dependency.new(name: "left-pad", requirements: [], package_manager: "dummy")]
      end

      it "ignores it" do
        expect(detector.transitive_changes).to be_empty
      end
    end
  end

  describe "#blocked_changes" do
    let(:previous_dependencies) { [transitive_dependency(name: "left-pad", version: "1.0.0")] }
    let(:current_dependencies) { [transitive_dependency(name: "left-pad", version: "1.1.0")] }

    context "when a changed transitive dependency matches a blocked version" do
      let(:blocked_versions) do
        [blocked_version(name: "left-pad", requirement: "= 1.1.0", reason: "malware")]
      end

      it "flags the change as blocked with the matching requirement and reason" do
        change = detector.blocked_changes.first

        expect(detector.blocked_changes.size).to eq(1)
        expect(change.name).to eq("left-pad")
        expect(change.new_version).to eq("1.1.0")
        expect(change.blocked_requirement).to eq("= 1.1.0")
        expect(change.reason).to eq("malware")
        expect(change).to be_blocked
      end
    end

    context "when the blocked requirement is a range that matches" do
      let(:blocked_versions) do
        [blocked_version(name: "left-pad", requirement: "> 1.0.0")]
      end

      it "flags the change as blocked" do
        expect(detector.blocked_changes.map(&:name)).to eq(["left-pad"])
      end
    end

    context "when the new version does not match the blocked requirement" do
      let(:blocked_versions) do
        [blocked_version(name: "left-pad", requirement: "= 2.0.0")]
      end

      it "does not flag the change as blocked" do
        expect(detector.blocked_changes).to be_empty
        expect(detector.transitive_changes.size).to eq(1)
      end
    end

    context "when the blocked dependency is not the one that changed" do
      let(:blocked_versions) do
        [blocked_version(name: "right-pad", requirement: "= 1.1.0")]
      end

      it "does not flag any change as blocked" do
        expect(detector.blocked_changes).to be_empty
      end
    end

    context "when a blocked entry is malformed" do
      let(:blocked_versions) do
        [
          blocked_version(name: nil, requirement: "= 1.1.0"),
          blocked_version(name: "left-pad", requirement: nil)
        ]
      end

      it "ignores malformed entries" do
        expect(detector.blocked_changes).to be_empty
      end
    end

    context "when the blocked version is only a pre-existing (unchanged) version" do
      let(:previous_dependencies) { [transitive_dependency(name: "left-pad", version: "1.1.0")] }
      let(:current_dependencies) { [transitive_dependency(name: "left-pad", version: "1.1.0")] }
      let(:blocked_versions) do
        [blocked_version(name: "left-pad", requirement: "= 1.1.0")]
      end

      it "does not block an update that did not change the dependency" do
        expect(detector.blocked_changes).to be_empty
      end
    end
  end
end
