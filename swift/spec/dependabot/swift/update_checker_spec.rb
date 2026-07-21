# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_commit_checker"
require "dependabot/git_tag_details"
require "dependabot/package/release_cooldown_options"
require "dependabot/swift/file_parser"
require "dependabot/swift/update_checker"
require "dependabot/swift/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Swift::UpdateChecker do
  let(:stub_upload_pack) do
    stub_request(:get, "#{url}.git/info/refs?service=git-upload-pack")
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end
  let(:dependency) { dependencies.find { |dep| dep.name == name } }
  let(:file_parser) do
    Dependabot::Swift::FileParser.new(
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      source: nil
    )
  end
  let(:dependencies) do
    file_parser.parse
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:dependency_files) { project_dependency_files(project_name, directory: directory) }
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:directory) { "/" }
  let(:project_name) { "ReactiveCocoa" }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end

  it_behaves_like "an update checker"

  context "with an up to date dependency" do
    let(:name) { "github.com/reactivecocoa/reactiveswift" }
    let(:url) { "https://github.com/ReactiveCocoa/ReactiveSwift" }
    let(:upload_pack_fixture) { "reactive-swift" }

    before { stub_upload_pack }

    describe "#can_update?" do
      subject { checker.can_update?(requirements_to_unlock: :own) }

      it { is_expected.to be_falsey }
    end

    describe "#latest_version" do
      subject { checker.latest_version }

      it { is_expected.to eq(dependency.version) }
    end

    describe "#latest_resolvable_version" do
      subject { checker.latest_resolvable_version }

      it { is_expected.to eq(dependency.version) }
    end
  end

  context "with a dependency that needs only lockfile changes to get updated" do
    let(:name) { "github.com/quick/quick" }
    let(:url) { "https://github.com/Quick/Quick" }
    let(:upload_pack_fixture) { "quick" }

    before { stub_upload_pack }

    describe "#can_update?" do
      subject { checker.can_update?(requirements_to_unlock: :own) }

      it { is_expected.to be_truthy }
    end

    describe "#latest_version" do
      subject { checker.latest_version }

      it { is_expected.to eq("7.0.2") }
    end

    describe "#latest_resolvable_version" do
      subject { checker.latest_resolvable_version }

      it { is_expected.to eq("7.0.2") }
    end

    describe "#updated_requirements" do
      subject(:updated_requirements) { checker.updated_requirements }

      it "does not update them" do
        expect(updated_requirements.first.requirement).to eq(">= 7.0.0, < 8.0.0")
      end
    end
  end

  shared_examples_for "a dependency that needs manifest changes to get updated" do
    let(:name) { "github.com/quick/nimble" }
    let(:url) { "https://github.com/Quick/Nimble" }
    let(:upload_pack_fixture) { "nimble" }

    before { stub_upload_pack }

    describe "#can_update?" do
      subject { checker.can_update?(requirements_to_unlock: :own) }

      it { is_expected.to be_truthy }
    end

    describe "#latest_version" do
      subject { checker.latest_version }

      it { is_expected.to eq("12.0.1") }
    end

    describe "#latest_resolvable_version" do
      subject { checker.latest_resolvable_version }

      it { is_expected.to eq("12.0.1") }
    end

    describe "#updated_requirements" do
      subject(:updated_requirements) { checker.updated_requirements }

      it "updates them to match new version" do
        expect(updated_requirements.first.requirement).to eq("= 12.0.1")
      end
    end
  end

  it_behaves_like "a dependency that needs manifest changes to get updated"

  context "when there's no lockfile" do
    let(:project_name) { "ReactiveCocoaNoLockfile" }

    it_behaves_like "a dependency that needs manifest changes to get updated"
  end

  context "when dependencies located in a project subfolder" do
    let(:name) { "github.com/quick/nimble" }
    let(:url) { "https://github.com/Quick/Nimble" }
    let(:upload_pack_fixture) { "nimble" }
    let(:directory) { "subfolder" }
    let(:project_name) { "ReactiveCocoaNested" }

    before { stub_upload_pack }

    describe "#can_update?" do
      subject { checker.can_update?(requirements_to_unlock: :own) }

      it { is_expected.to be_truthy }
    end

    describe "#latest_version" do
      subject { checker.latest_version }

      it { is_expected.to eq("12.0.1") }
    end

    describe "#latest_resolvable_version" do
      subject { checker.latest_resolvable_version }

      it { is_expected.to eq("12.0.1") }
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    let(:name) { "github.com/quick/nimble" }
    let(:url) { "https://github.com/Quick/Nimble" }
    let(:upload_pack_fixture) { "nimble" }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: name,
          package_manager: "swift",
          vulnerable_versions: ["<= 9.2.1"]
        )
      ]
    end

    before { stub_upload_pack }

    context "when a supported newer version is available" do
      it "updates to the least new supported version" do
        expect(lowest_security_fix_version).to eq(Dependabot::Swift::Version.new("10.0.0"))
      end
    end

    context "when tag details contain generic Gem::Version values" do
      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions)
          .and_return(
            [
              Dependabot::GitTagDetails.new(tag: "10.0.0", version: Gem::Version.new("10.0.0")),
              Dependabot::GitTagDetails.new(tag: "11.0.0", version: Gem::Version.new("11.0.0"))
            ]
          )
      end

      it "returns a Swift version" do
        expect(lowest_security_fix_version).to eq(Dependabot::Swift::Version.new("10.0.0"))
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["= 10.0.0"] }

      it "doesn't return ignored versions" do
        expect(lowest_security_fix_version).to eq(Dependabot::Swift::Version.new("11.0.0"))
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { checker.lowest_resolvable_security_fix_version }

    context "when a supported newer version is available, and resolvable" do
      let(:name) { "github.com/quick/nimble" }
      let(:url) { "https://github.com/Quick/Nimble" }
      let(:upload_pack_fixture) { "nimble" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: name,
            package_manager: "swift",
            vulnerable_versions: ["<= 9.2.1"]
          )
        ]
      end

      before { stub_upload_pack }

      it "updates to the least new supported version" do
        expect(lowest_resolvable_security_fix_version).to eq(Dependabot::Swift::Version.new("10.0.0"))
      end

      context "with ignored versions" do
        let(:ignored_versions) { ["= 10.0.0"] }

        it "doesn't return ignored versions" do
          expect(lowest_resolvable_security_fix_version).to eq(Dependabot::Swift::Version.new("11.0.0"))
        end
      end
    end

    context "when fixed version has conflicts with the project" do
      let(:project_name) { "conflicts" }

      let(:name) { "github.com/vapor/vapor" }
      let(:url) { "https://github.com/vapor/vapor" }
      let(:upload_pack_fixture) { "vapor" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: name,
            package_manager: "swift",
            vulnerable_versions: ["<= 4.6.2"]
          )
        ]
      end

      before { stub_upload_pack }

      it { is_expected.to be_nil }
    end
  end

  context "with Xcode SPM projects" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        ),
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: fixture(
            "projects",
            project_name,
            "MyApp.xcodeproj",
            "project.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
        )
      ]
    end
    let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
    let(:file_parser) do
      Dependabot::Swift::FileParser.new(
        dependency_files: dependency_files,
        repo_contents_path: repo_contents_path,
        source: nil
      )
    end
    let(:dependencies) { file_parser.parse }
    let(:dependency) { dependencies.find { |dep| dep.name == name } }

    let(:stub_xcode_upload_pack) do
      stub_request(:get, "#{url}.git/info/refs?service=git-upload-pack")
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", upload_pack_fixture),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    context "with Xcode project that needs update (v2 resolved)" do
      let(:project_name) { "xcode_project_needs_update" }
      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      before { stub_xcode_upload_pack }

      describe "#can_update?" do
        subject { checker.can_update?(requirements_to_unlock: :own) }

        it { is_expected.to be_truthy }
      end

      describe "#latest_version" do
        subject(:latest_version) { checker.latest_version }

        it "returns latest version from git tags" do
          expect(latest_version).to be_a(Dependabot::Swift::Version)
          expect(latest_version.to_s).to eq("7.0.2")
        end

        context "when tag details contain a generic Gem::Version" do
          before do
            allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
              .to receive(:local_tag_for_latest_version)
              .and_return(
                Dependabot::GitTagDetails.new(
                  tag: "7.0.2",
                  version: Gem::Version.new("7.0.2"),
                  commit_sha: "abc123"
                )
              )
          end

          it "returns a Swift version" do
            expect(latest_version).to eq(Dependabot::Swift::Version.new("7.0.2"))
          end
        end
      end

      describe "#latest_resolvable_version" do
        subject(:latest_resolvable_version) { checker.latest_resolvable_version }

        it "returns the latest version that satisfies requirements" do
          expect(latest_resolvable_version).to be_a(Dependabot::Swift::Version)
          expect(latest_resolvable_version.to_s).to eq("7.0.2")
        end
      end

      describe "#updated_requirements" do
        subject(:updated_requirements) { checker.updated_requirements }

        it "returns updated requirements with new version" do
          expect(updated_requirements.first.requirement).to eq(">= 7.0.2, < 8.0.0")
          expect(updated_requirements.first.file).to eq("MyApp.xcodeproj/project.pbxproj")
        end

        it "updates the source ref to the commit SHA" do
          # The ref should be a git commit SHA (40 hex chars) for Package.resolved
          expect(updated_requirements.first.source_string(:ref)).to match(/\A[0-9a-f]{40}\z/)
        end
      end
    end

    context "with Xcode project that is up to date" do
      let(:project_name) { "xcode_project_up_to_date" }
      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      before { stub_xcode_upload_pack }

      describe "#can_update?" do
        subject { checker.can_update?(requirements_to_unlock: :own) }

        it { is_expected.to be_falsey }
      end

      describe "#latest_version" do
        subject { checker.latest_version }

        it { is_expected.to eq(dependency.version) }
      end

      describe "#latest_resolvable_version" do
        subject { checker.latest_resolvable_version }

        it { is_expected.to eq(dependency.version) }
      end
    end

    context "with Xcode project pinned to branch" do
      let(:project_name) { "xcode_project_branch_pin" }
      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      before { stub_xcode_upload_pack }

      describe "#latest_version" do
        subject { checker.latest_version }

        # Branch-pinned dependencies don't have a semver version
        it { is_expected.to be_nil }
      end
    end

    context "with Xcode project pinned to exact version" do
      let(:project_name) { "xcode_project_exact_version" }
      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      before { stub_xcode_upload_pack }

      describe "#can_update?" do
        subject { checker.can_update?(requirements_to_unlock: :own) }

        it { is_expected.to be_truthy }
      end

      describe "#latest_version" do
        subject(:latest_version) { checker.latest_version }

        it "returns latest version from git tags" do
          expect(latest_version).to be_a(Dependabot::Swift::Version)
          expect(latest_version.to_s).to eq("7.0.2")
        end
      end

      describe "#latest_resolvable_version" do
        subject(:latest_resolvable_version) { checker.latest_resolvable_version }

        it "returns the latest version despite exactVersion constraint" do
          expect(latest_resolvable_version).to be_a(Dependabot::Swift::Version)
          expect(latest_resolvable_version.to_s).to eq("7.0.2")
        end
      end

      describe "#updated_requirements" do
        subject(:updated_requirements) { checker.updated_requirements }

        it "returns updated requirements with new exact version" do
          expect(updated_requirements.first.requirement).to eq("= 7.0.2")
          expect(updated_requirements.first.file).to eq("MyApp.xcodeproj/project.pbxproj")
          expect(updated_requirements.first.metadata_string(:kind)).to eq("exactVersion")
          expect(updated_requirements.first.metadata_string(:requirement_string)).to eq("exact: \"7.0.2\"")
        end

        it "updates the source ref to the commit SHA" do
          # The ref should be a git commit SHA (40 hex chars) for Package.resolved
          expect(updated_requirements.first.source_string(:ref)).to match(/\A[0-9a-f]{40}\z/)
        end
      end
    end

    context "with Xcode project pinned to upToNextMinorVersion" do
      let(:project_name) { "xcode_project_minor_version" }
      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      before { stub_xcode_upload_pack }

      describe "#can_update?" do
        subject { checker.can_update?(requirements_to_unlock: :own) }

        it { is_expected.to be_truthy }
      end

      describe "#latest_version" do
        subject(:latest_version) { checker.latest_version }

        it "returns latest version from git tags" do
          expect(latest_version).to be_a(Dependabot::Swift::Version)
          expect(latest_version.to_s).to eq("7.0.2")
        end
      end

      describe "#latest_resolvable_version" do
        subject(:latest_resolvable_version) { checker.latest_resolvable_version }

        it "returns the latest version despite upToNextMinorVersion constraint" do
          expect(latest_resolvable_version).to be_a(Dependabot::Swift::Version)
          expect(latest_resolvable_version.to_s).to eq("7.0.2")
        end
      end

      describe "#updated_requirements" do
        subject(:updated_requirements) { checker.updated_requirements }

        it "returns updated requirements with new minor version range" do
          expect(updated_requirements.first.requirement).to eq(">= 7.0.2, < 7.1.0")
          expect(updated_requirements.first.file).to eq("MyApp.xcodeproj/project.pbxproj")
          expect(updated_requirements.first.metadata_string(:kind)).to eq("upToNextMinorVersion")
          expect(updated_requirements.first.metadata_string(:requirement_string))
            .to eq(".upToNextMinor(from: \"7.0.2\")")
        end

        it "updates the source ref to the commit SHA" do
          expect(updated_requirements.first.source_string(:ref)).to match(/\A[0-9a-f]{40}\z/)
        end
      end
    end

    context "with Xcode project using versionRange" do
      let(:project_name) { "xcode_project_version_range" }
      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      before { stub_xcode_upload_pack }

      describe "#can_update?" do
        subject { checker.can_update?(requirements_to_unlock: :own) }

        it { is_expected.to be_truthy }
      end

      describe "#latest_version" do
        subject(:latest_version) { checker.latest_version }

        it "returns latest version from git tags" do
          expect(latest_version).to be_a(Dependabot::Swift::Version)
          expect(latest_version.to_s).to eq("7.0.2")
        end
      end

      describe "#latest_resolvable_version" do
        subject(:latest_resolvable_version) { checker.latest_resolvable_version }

        it "returns the highest version within the range constraint" do
          # Latest is 7.0.2 but maximumVersion is 7.0.1, so we expect 7.0.0
          expect(latest_resolvable_version).to be_a(Dependabot::Swift::Version)
          expect(latest_resolvable_version.to_s).to eq("7.0.0")
        end
      end

      describe "#updated_requirements" do
        subject(:updated_requirements) { checker.updated_requirements }

        it "returns updated requirements with version within range" do
          # minimum is updated to target version, maximum stays the same
          expect(updated_requirements.first.requirement).to eq(">= 7.0.0, < 7.0.1")
          expect(updated_requirements.first.file).to eq("MyApp.xcodeproj/project.pbxproj")
          expect(updated_requirements.first.metadata_string(:kind)).to eq("versionRange")
        end

        it "updates the source ref to the commit SHA" do
          expect(updated_requirements.first.source_string(:ref)).to match(/\A[0-9a-f]{40}\z/)
        end
      end
    end

    context "with multiple Xcode projects" do
      let(:project_name) { "xcode_project_needs_update" }
      # Use the same fixture format as single xcode project but for multi-project test
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "AppA.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "AppA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            content: fixture(
              "projects",
              project_name,
              "MyApp.xcodeproj",
              "project.xcworkspace",
              "xcshareddata",
              "swiftpm",
              "Package.resolved"
            )
          )
        ]
      end

      let(:name) { "github.com/quick/quick" }
      let(:url) { "https://github.com/Quick/Quick" }
      let(:upload_pack_fixture) { "quick" }

      # Directly construct multiple dependencies to test multi-project behavior
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: name,
            version: "7.0.0",
            requirements: [
              {
                file: "AppA.xcodeproj/project.pbxproj",
                requirement: ">= 7.0.0, < 8.0.0",
                groups: [],
                source: { type: "git", url: "https://github.com/Quick/Quick.git", ref: "7.0.0", branch: nil },
                metadata: { kind: "upToNextMajorVersion", requirement_string: "from: \"7.0.0\"" }
              }
            ],
            package_manager: "swift"
          )
        ]
      end
      let(:dependency) { dependencies.first }

      before { stub_xcode_upload_pack }

      describe "#can_update?" do
        subject { checker.can_update?(requirements_to_unlock: :own) }

        it { is_expected.to be_truthy }
      end
    end

    context "with revision-only pinned dependency" do
      let(:project_name) { "xcode_project_revision_only" }
      let(:name) { "github.com/apple/swift-nio" }
      let(:url) { "https://github.com/apple/swift-nio" }

      # No upload pack stub needed - revision-only dependencies return nil immediately
      # without making git requests

      describe "#latest_version" do
        subject { checker.latest_version }

        # Revision-pinned dependencies don't have a semver version
        it { is_expected.to be_nil }
      end
    end
  end

  describe "#latest_version with git-tag cooldown" do
    let(:cooldown_dependency) do
      Dependabot::Dependency.new(
        name: "github.com/apple/swift-nio",
        version: "2.0.0",
        requirements: [{
          file: "Package.swift",
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/apple/swift-nio",
            ref: "2.0.0",
            branch: nil
          }
        }],
        package_manager: "swift"
      )
    end
    let(:cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90)
    end
    let(:cooldown_checker) do
      described_class.new(
        dependency: cooldown_dependency,
        dependency_files: [],
        repo_contents_path: nil,
        credentials: github_credentials,
        update_cooldown: cooldown_options
      )
    end
    let(:stubbed_git_commit_checker) { instance_double(Dependabot::GitCommitChecker) }
    let(:newer_tag) do
      Dependabot::GitTagDetails.new(
        tag: "2.1.0",
        version: Gem::Version.new("2.1.0"),
        commit_sha: "abc123",
        tag_sha: "def456"
      )
    end

    before do
      allow(Dependabot::GitCommitChecker).to receive(:new).and_return(stubbed_git_commit_checker)
      allow(stubbed_git_commit_checker).to receive_messages(
        git_dependency?: true,
        pinned_ref_looks_like_version?: true
      )
    end

    context "when every candidate tag is still within its cooldown window" do
      before do
        allow(stubbed_git_commit_checker)
          .to receive(:local_tag_for_latest_version)
          .with(cooldown_options)
          .and_return(nil)
      end

      it "proposes no update" do
        expect(cooldown_checker.latest_version).to be_nil
      end
    end

    context "when a tag is available outside the cooldown window" do
      before do
        allow(stubbed_git_commit_checker)
          .to receive(:local_tag_for_latest_version)
          .with(cooldown_options)
          .and_return(newer_tag)
      end

      it "returns that version" do
        expect(cooldown_checker.latest_version).to eq(Dependabot::Swift::Version.new("2.1.0"))
      end

      it "forwards the configured cooldown window to the git commit checker" do
        cooldown_checker.latest_version
        expect(stubbed_git_commit_checker)
          .to have_received(:local_tag_for_latest_version).with(cooldown_options).at_least(:once)
      end
    end

    context "when cooldown is not configured" do
      let(:cooldown_options) { nil }

      before do
        allow(stubbed_git_commit_checker)
          .to receive(:local_tag_for_latest_version)
          .with(nil)
          .and_return(newer_tag)
      end

      it "skips cooldown filtering and returns the newest tag" do
        expect(cooldown_checker.latest_version).to eq(Dependabot::Swift::Version.new("2.1.0"))
        expect(stubbed_git_commit_checker)
          .to have_received(:local_tag_for_latest_version).with(nil).at_least(:once)
      end
    end
  end
end
