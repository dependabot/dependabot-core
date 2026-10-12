# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/swift/file_updater/pbxproj_updater"

RSpec.describe Dependabot::Swift::FileUpdater::PbxprojUpdater do
  subject(:updater) do
    described_class.new(
      pbxproj_file: pbxproj_file,
      dependencies: dependencies
    )
  end

  describe "#updated_pbxproj_content" do
    subject(:updated_content) { updater.updated_pbxproj_content }

    context "with upToNextMajorVersion requirement" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.55.0",
            previous_version: "2.54.0",
            requirements: [{
              requirement: ">= 2.55.0, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-nio.git",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: "from: \"2.55.0\"",
                kind: "upToNextMajorVersion"
              }
            }],
            previous_requirements: [{
              requirement: ">= 2.54.0, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-nio.git",
                ref: "old123",
                branch: nil
              },
              metadata: {
                requirement_string: "from: \"2.54.0\"",
                kind: "upToNextMajorVersion"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it "updates the minimumVersion" do
        expect(updated_content).to include("minimumVersion = 2.55.0;")
        expect(updated_content).not_to include("minimumVersion = 2.54.0;")
      end

      it "preserves the kind" do
        expect(updated_content).to include("kind = upToNextMajorVersion;")
      end

      it "preserves the repositoryURL" do
        expect(updated_content).to include('repositoryURL = "https://github.com/apple/swift-nio.git"')
      end
    end

    context "with exactVersion requirement" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project_exact_version", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/quick/quick",
            version: "7.1.0",
            previous_version: "7.0.0",
            requirements: [{
              requirement: "= 7.1.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/Quick/Quick.git",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: "exact: \"7.1.0\"",
                kind: "exactVersion"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "quick" }
          )
        ]
      end

      it "updates the version field" do
        expect(updated_content).to include("version = 7.1.0;")
        expect(updated_content).not_to include("version = 7.0.0;")
      end

      it "preserves the kind" do
        expect(updated_content).to include("kind = exactVersion;")
      end
    end

    context "with exactVersion requirement using minimumVersion field" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project_multi_req", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-argument-parser",
            version: "1.3.0",
            previous_version: "1.2.0",
            requirements: [{
              requirement: "= 1.3.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-argument-parser",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: "exact: \"1.3.0\"",
                kind: "exactVersion"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-argument-parser" }
          )
        ]
      end

      it "updates the minimumVersion field" do
        expect(updated_content).to include("minimumVersion = 1.3.0;")
        expect(updated_content).not_to include("minimumVersion = 1.2.0;")
      end

      it "preserves the kind" do
        expect(updated_content).to include("kind = exactVersion;")
      end

      it "does not modify other dependencies" do
        expect(updated_content).to include("minimumVersion = 2.54.0;")
        expect(updated_content).to include("minimumVersion = 1.0.0;")
        expect(updated_content).to include("minimumVersion = 1.4.0;")
      end
    end

    context "with upToNextMinorVersion requirement" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project_minor_version", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/quick/quick",
            version: "7.0.2",
            previous_version: "7.0.0",
            requirements: [{
              requirement: ">= 7.0.2, < 7.1.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/Quick/Quick.git",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: ".upToNextMinor(from: \"7.0.2\")",
                kind: "upToNextMinorVersion"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "quick" }
          )
        ]
      end

      it "updates the minimumVersion" do
        expect(updated_content).to include("minimumVersion = 7.0.2;")
        expect(updated_content).not_to include("minimumVersion = 7.0.0;")
      end

      it "preserves the kind" do
        expect(updated_content).to include("kind = upToNextMinorVersion;")
      end
    end

    context "with prerelease minimumVersion" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: <<~PBX,
            // !$*UTF8*$!
            {
              objects = {
                123 = {
                  isa = XCRemoteSwiftPackageReference;
                  repositoryURL = "https://github.com/apple/swift-nio.git";
                  requirement = {
                    kind = upToNextMajorVersion;
                    minimumVersion = 2.54.0-beta.1;
                  };
                };
              };
              rootObject = 123;
            }
          PBX
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.55.0-beta.2",
            previous_version: "2.54.0-beta.1",
            requirements: [{
              requirement: ">= 2.55.0-beta.2, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-nio.git",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: "from: \"2.55.0-beta.2\"",
                kind: "upToNextMajorVersion"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it "updates the prerelease minimumVersion" do
        expect(updated_content).to include("minimumVersion = 2.55.0-beta.2;")
        expect(updated_content).not_to include("minimumVersion = 2.54.0-beta.1;")
      end
    end

    context "with versionRange requirement" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project_version_range", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/quick/quick",
            version: "6.0.0",
            previous_version: "5.1.0",
            requirements: [{
              requirement: ">= 6.0.0, < 7.0.1",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/Quick/Quick.git",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: "\"6.0.0\"..<\"7.0.1\"",
                kind: "versionRange"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "quick" }
          )
        ]
      end

      it "updates the minimumVersion" do
        expect(updated_content).to include("minimumVersion = 6.0.0;")
        expect(updated_content).not_to include("minimumVersion = 5.1.0;")
      end

      it "preserves the maximumVersion" do
        expect(updated_content).to include("maximumVersion = 7.0.1;")
      end

      it "preserves the kind" do
        expect(updated_content).to include("kind = versionRange;")
      end
    end

    context "with branch requirement" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project_branch_pin", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/quick/quick",
            version: nil,
            requirements: [{
              requirement: nil,
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/Quick/Quick.git",
                ref: "main",
                branch: "main"
              },
              metadata: {
                kind: "branch"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "quick" }
          )
        ]
      end

      it "does not modify the content" do
        expect(updated_content).to eq(pbxproj_file.content)
      end
    end

    context "with multiple dependencies" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project_multi_req", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.55.0",
            previous_version: "2.54.0",
            requirements: [{
              requirement: ">= 2.55.0, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-nio.git",
                ref: "abc123",
                branch: nil
              },
              metadata: {
                requirement_string: "from: \"2.55.0\"",
                kind: "upToNextMajorVersion"
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it "only updates the matching dependency" do
        expect(updated_content).to include("minimumVersion = 2.55.0;")
        expect(updated_content).not_to include("minimumVersion = 2.54.0;")
        # swift-collections should remain unchanged
        expect(updated_content).to include("minimumVersion = 1.0.0;")
      end
    end

    context "when dependency does not match any pbxproj entry" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: fixture("projects", "xcode_project", "MyApp.xcodeproj", "project.pbxproj"),
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/unknown/package",
            version: "1.0.0",
            requirements: [{
              requirement: ">= 1.0.0, < 2.0.0",
              groups: ["dependencies"],
              file: "OtherApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/unknown/package.git",
                ref: "abc123",
                branch: nil
              }
            }],
            package_manager: "swift",
            metadata: { identity: "package" }
          )
        ]
      end

      it "does not modify the content" do
        expect(updated_content).to eq(pbxproj_file.content)
      end
    end

    context "when pbxproj file has nil content" do
      let(:pbxproj_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.pbxproj",
          content: nil,
          support_file: true
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.55.0",
            requirements: [],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it "raises DependencyFileNotParseable" do
        expect { updated_content }.to raise_error(
          Dependabot::DependencyFileNotParseable,
          /has no content/
        )
      end
    end
  end
end
