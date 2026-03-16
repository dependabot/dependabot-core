# typed: false
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/swift/file_updater/xcode_lockfile_updater"

RSpec.describe Dependabot::Swift::FileUpdater::XcodeLockfileUpdater do
  subject(:updater) do
    described_class.new(
      resolved_file: resolved_file,
      dependencies: dependencies
    )
  end

  describe "#updated_lockfile_content" do
    subject(:updated_content) { updater.updated_lockfile_content }

    context "with v2 Package.resolved" do
      let(:resolved_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: fixture(
            "projects",
            "xcode_project",
            "MyApp.xcodeproj",
            "project.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
        )
      end

      context "when updating version" do
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
                  ref: "abc123def456",
                  branch: nil
                }
              }],
              previous_requirements: [{
                requirement: ">= 2.54.0, < 3.0.0",
                groups: ["dependencies"],
                file: "MyApp.xcodeproj/project.pbxproj",
                source: {
                  type: "git",
                  url: "https://github.com/apple/swift-nio.git",
                  ref: "6213ba7a06febe8fef60563a4a7d26a4085783cf",
                  branch: nil
                }
              }],
              package_manager: "swift",
              metadata: { identity: "swift-nio" }
            )
          ]
        end

        it "updates the version in Package.resolved" do
          expect(updated_content).to include('"version" : "2.55.0"')
          expect(updated_content).not_to include('"version" : "2.54.0"')
        end

        it "preserves the schema version" do
          parsed = JSON.parse(updated_content)
          expect(parsed["version"]).to eq(2)
        end

        it "preserves the identity and location" do
          parsed = JSON.parse(updated_content)
          pin = parsed["pins"].first
          expect(pin["identity"]).to eq("swift-nio")
          expect(pin["location"]).to eq("https://github.com/apple/swift-nio.git")
        end
      end

      context "when dependency is not in resolved file" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "github.com/vapor/vapor",
              version: "4.0.0",
              requirements: [{
                requirement: ">= 4.0.0, < 5.0.0",
                groups: ["dependencies"],
                file: "MyApp.xcodeproj/project.pbxproj",
                source: {
                  type: "git",
                  url: "https://github.com/vapor/vapor.git",
                  ref: "4.0.0",
                  branch: nil
                }
              }],
              package_manager: "swift",
              metadata: { identity: "vapor" }
            )
          ]
        end

        it "leaves the file unchanged" do
          parsed = JSON.parse(updated_content)
          expect(parsed["pins"].length).to eq(1)
          expect(parsed["pins"].first["identity"]).to eq("swift-nio")
          expect(parsed["pins"].first["state"]["version"]).to eq("2.54.0")
        end
      end
    end

    context "with v1 Package.resolved" do
      let(:resolved_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: fixture(
            "projects",
            "xcode_project_v1_resolved",
            "MyApp.xcodeproj",
            "project.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
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
                ref: "newrevision123",
                branch: nil
              }
            }],
            previous_requirements: [{
              requirement: ">= 2.54.0, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-nio.git",
                ref: "6213ba7a06febe8fef60563a4a7d26a4085783cf",
                branch: nil
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it "updates the version while preserving v1 format" do
        parsed = JSON.parse(updated_content)
        expect(parsed["version"]).to eq(1)
        expect(parsed["object"]["pins"].first["state"]["version"]).to eq("2.55.0")
      end

      it "preserves v1-specific keys" do
        parsed = JSON.parse(updated_content)
        pin = parsed["object"]["pins"].first
        expect(pin).to have_key("package")
        expect(pin).to have_key("repositoryURL")
      end
    end

    context "with v3 Package.resolved" do
      let(:resolved_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: fixture(
            "projects",
            "xcode_project_v3_resolved",
            "MyApp.xcodeproj",
            "project.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.60.0",
            previous_version: "2.54.0",
            requirements: [{
              requirement: ">= 2.60.0, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-nio.git",
                ref: "newrev456",
                branch: nil
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it "updates the version while preserving v3 format" do
        parsed = JSON.parse(updated_content)
        expect(parsed["version"]).to eq(3)
        expect(parsed["pins"].first["state"]["version"]).to eq("2.60.0")
      end
    end

    context "with invalid JSON" do
      let(:resolved_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: "{ invalid json"
        )
      end

      let(:dependencies) { [] }

      it "raises DependencyFileNotParseable" do
        expect { updated_content }
          .to raise_error(Dependabot::DependencyFileNotParseable, /not valid JSON/)
      end
    end

    context "with unsupported schema version" do
      let(:resolved_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: '{ "version": 99, "pins": [] }'
        )
      end

      let(:dependencies) { [] }

      it "raises DependencyFileNotParseable" do
        expect { updated_content }
          .to raise_error(Dependabot::DependencyFileNotParseable, /unsupported schema version/)
      end
    end
  end

  describe "#lockfile_changed?" do
    subject { updater.lockfile_changed? }

    let(:resolved_file) do
      Dependabot::DependencyFile.new(
        name: "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        content: fixture(
          "projects",
          "xcode_project",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      )
    end

    context "when dependency matches the resolved file" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.55.0",
            requirements: [{
              requirement: ">= 2.55.0, < 3.0.0",
              groups: ["dependencies"],
              file: "MyApp.xcodeproj/project.pbxproj",
              source: { type: "git", url: "https://github.com/apple/swift-nio.git", ref: "2.55.0" }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it { is_expected.to be(true) }
    end

    context "when dependency does not match the resolved file" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-collections",
            version: "1.0.5",
            requirements: [{
              requirement: ">= 1.0.5, < 2.0.0",
              groups: ["dependencies"],
              file: "OtherApp.xcodeproj/project.pbxproj",
              source: { type: "git", url: "https://github.com/apple/swift-collections.git", ref: "1.0.5" }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-collections" }
          )
        ]
      end

      it { is_expected.to be(false) }
    end

    context "when resolved file is workspace-scoped and dependency comes from sibling project" do
      let(:resolved_file) do
        Dependabot::DependencyFile.new(
          name: "MyApp.xcworkspace/xcshareddata/swiftpm/Package.resolved",
          content: fixture(
            "projects",
            "xcode_workspace",
            "MyApp.xcworkspace",
            "xcshareddata",
            "swiftpm",
            "Package.resolved"
          )
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-nio",
            version: "2.55.0",
            requirements: [{
              requirement: ">= 2.55.0, < 3.0.0",
              groups: ["dependencies"],
              file: "AppA.xcodeproj/project.pbxproj",
              source: { type: "git", url: "https://github.com/apple/swift-nio.git", ref: "2.55.0" }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-nio" }
          )
        ]
      end

      it { is_expected.to be(true) }
    end
  end
end
