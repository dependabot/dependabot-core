# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/update_checker/xcode_version_resolver"
require "dependabot/dependency"
require "dependabot/git_commit_checker"
require "dependabot/security_advisory"
require "dependabot/swift/version"

RSpec.describe Dependabot::Swift::UpdateChecker::XcodeVersionResolver do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/quick/quick",
      version: "7.0.0",
      requirements: requirements,
      package_manager: "swift"
    )
  end

  let(:requirements) do
    [{
      file: "MyApp.xcodeproj/project.pbxproj",
      requirement: ">= 7.0.0, < 8.0.0",
      groups: [],
      source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
      metadata: { kind: requirement_kind, requirement_string: "from: \"7.0.0\"" }
    }]
  end

  let(:requirement_kind) { "upToNextMajorVersion" }

  let(:git_commit_checker) do
    instance_double(Dependabot::GitCommitChecker)
  end

  let(:security_advisories) { [] }

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      git_commit_checker: git_commit_checker,
      security_advisories: security_advisories
    )
  end

  let(:latest_tag) do
    {
      tag: "7.0.2",
      version: Dependabot::Swift::Version.new("7.0.2"),
      commit_sha: "91132c0fe9a98e76f3d7381a608685aa41770706",
      tag_sha: "abc123"
    }
  end

  describe "#latest_resolvable_version_tag" do
    before do
      allow(git_commit_checker).to receive(:local_tag_for_latest_version).and_return(latest_tag)
    end

    it "returns the full tag hash including commit_sha" do
      tag = resolver.latest_resolvable_version_tag
      expect(tag).to be_a(Hash)
      expect(tag[:version]).to eq(Dependabot::Swift::Version.new("7.0.2"))
      expect(tag[:commit_sha]).to eq("91132c0fe9a98e76f3d7381a608685aa41770706")
    end

    it "is memoized" do
      resolver.latest_resolvable_version_tag
      resolver.latest_resolvable_version_tag
      expect(git_commit_checker).to have_received(:local_tag_for_latest_version).once
    end

    context "when dependency version is not pinned" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "github.com/quick/quick",
          version: nil,
          requirements: requirements,
          package_manager: "swift"
        )
      end

      it "returns nil" do
        expect(resolver.latest_resolvable_version_tag).to be_nil
      end
    end
  end

  describe "#latest_resolvable_version" do
    before do
      allow(git_commit_checker).to receive(:local_tag_for_latest_version).and_return(latest_tag)
    end

    it "returns the version from the tag" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::Swift::Version.new("7.0.2"))
    end
  end

  describe "#version_meets_requirements?" do
    let(:version) { Dependabot::Swift::Version.new("8.0.0") }

    context "with exactVersion requirement kind" do
      let(:requirement_kind) { "exactVersion" }
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: "= 7.0.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: { kind: "exactVersion", requirement_string: "exact: \"7.0.0\"" }
        }]
      end

      it "returns true (allows any version since requirement will be updated)" do
        expect(resolver.send(:version_meets_requirements?, version)).to be true
      end
    end

    context "with upToNextMajorVersion requirement kind" do
      let(:requirement_kind) { "upToNextMajorVersion" }

      it "returns true (allows any version since requirement will be updated)" do
        expect(resolver.send(:version_meets_requirements?, version)).to be true
      end
    end

    context "with upToNextMinorVersion requirement kind" do
      let(:requirement_kind) { "upToNextMinorVersion" }
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: ">= 7.0.0, < 7.1.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: { kind: "upToNextMinorVersion", requirement_string: ".upToNextMinor(from: \"7.0.0\")" }
        }]
      end

      it "returns true (allows any version since requirement will be updated)" do
        expect(resolver.send(:version_meets_requirements?, version)).to be true
      end
    end

    context "with versionRange requirement kind" do
      let(:requirement_kind) { "versionRange" }
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: ">= 7.0.0, < 8.0.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: { kind: "versionRange", requirement_string: "\"7.0.0\"..<\"8.0.0\"" }
        }]
      end

      it "returns false when version exceeds upper bound" do
        expect(resolver.send(:version_meets_requirements?, version)).to be false
      end

      it "returns true when version is within range" do
        within_range_version = Dependabot::Swift::Version.new("7.5.0")
        expect(resolver.send(:version_meets_requirements?, within_range_version)).to be true
      end
    end

    context "with nil requirement kind" do
      let(:requirements) do
        [{
          file: "MyApp.xcodeproj/project.pbxproj",
          requirement: ">= 7.0.0, < 8.0.0",
          groups: [],
          source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
          metadata: {}
        }]
      end

      it "falls back to checking the requirement constraint" do
        expect(resolver.send(:version_meets_requirements?, version)).to be false
      end
    end
  end

  describe "#version_pinned?" do
    it "returns true when dependency has a valid version" do
      expect(resolver.version_pinned?).to be true
    end

    context "when dependency version is nil" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "github.com/quick/quick",
          version: nil,
          requirements: requirements,
          package_manager: "swift"
        )
      end

      it "returns false" do
        expect(resolver.version_pinned?).to be false
      end
    end

    context "when dependency version is a commit SHA" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "github.com/quick/quick",
          version: "91132c0fe9a98e76f3d7381a608685aa41770706",
          requirements: requirements,
          package_manager: "swift"
        )
      end

      it "returns false (SHA is not a valid semver)" do
        expect(resolver.version_pinned?).to be false
      end
    end
  end
end
