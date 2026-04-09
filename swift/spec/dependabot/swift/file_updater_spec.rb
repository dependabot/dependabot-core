# typed: false
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/experiments"
require "dependabot/swift/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Swift::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end
  let(:dependencies) { [] }
  let(:files) { project_dependency_files(project_name) }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:project_name) { "Example" }

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_dependency_files) { updater.updated_dependency_files }

    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "github.com/reactivecocoa/reactiveswift",
          version: "7.1.1",
          previous_version: "7.1.0",
          requirements: [{
            requirement: "= 7.1.1",
            groups: [],
            file: "Package.swift",
            source: {
              type: "git",
              url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
              ref: "7.1.0",
              branch: nil
            },
            metadata: {
              requirement_string: "exact: \"7.1.1\""
            }
          }],
          previous_requirements: [{
            requirement: "= 7.1.0",
            groups: [],
            file: "Package.swift",
            source: {
              type: "git",
              url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
              ref: "7.1.0",
              branch: nil
            },
            metadata: {
              declaration_string:
                ".package(url: \"https://github.com/ReactiveCocoa/ReactiveSwift.git\",\n             exact: \"7.1.0\")",
              requirement_string: "exact: \"7.1.0\""
            }
          }],
          package_manager: "swift",
          metadata: { identity: "reactiveswift" }
        )
      ]
    end

    it "updates the version in manifest and lockfile" do
      manifest = updated_dependency_files.find { |file| file.name == "Package.swift" }

      expect(manifest.content).to include(
        "url: \"https://github.com/ReactiveCocoa/ReactiveSwift.git\",\n             exact: \"7.1.1\""
      )

      lockfile = updated_dependency_files.find { |file| file.name == "Package.resolved" }

      expect(lockfile.content.gsub(/^ {4}/, "")).to include <<~RESOLVED
        {
          "identity" : "reactiveswift",
          "kind" : "remoteSourceControl",
          "location" : "https://github.com/ReactiveCocoa/ReactiveSwift.git",
          "state" : {
            "revision" : "40c465af19b993344e84355c00669ba2022ca3cd",
            "version" : "7.1.1"
          }
        },
      RESOLVED
    end

    context "when latest version is higher than target version" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-docc-plugin",
            version: "1.1.0",
            previous_version: "1.0.0",
            requirements: [{
              requirement: ">= 1.1.0, < 2.0.0",
              groups: [],
              file: "Package.swift",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-docc-plugin",
                ref: "1.0.0",
                branch: nil
              },
              metadata: {
                requirement_string: "from: \"1.1.0\""
              }
            }],
            previous_requirements: [{
              requirement: ">= 1.0.0, < 2.0.0",
              groups: [],
              file: "Package.swift",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-docc-plugin",
                ref: "1.0.0",
                branch: nil
              },
              metadata: {
                declaration_string:
                  ".package(\n      url: \"https://github.com/apple/swift-docc-plugin\",\n      from: \"1.0.0\")",
                requirement_string: "from: \"1.0.0\""
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-docc-plugin" }
          )
        ]
      end

      it "properly updates to target version in manifest and lockfile" do
        manifest = updated_dependency_files.find { |file| file.name == "Package.swift" }

        expect(manifest.content).to include(
          "url: \"https://github.com/apple/swift-docc-plugin\",\n      from: \"1.1.0\""
        )

        lockfile = updated_dependency_files.find { |file| file.name == "Package.resolved" }

        expect(lockfile.content.gsub(/^ {4}/, "")).to include <<~RESOLVED
          {
            "identity" : "swift-docc-plugin",
            "kind" : "remoteSourceControl",
            "location" : "https://github.com/apple/swift-docc-plugin",
            "state" : {
              "revision" : "10bc670db657d11bdd561e07de30a9041311b2b1",
              "version" : "1.1.0"
            }
          },
        RESOLVED
      end
    end
  end

  context "when enable_swift_xcode_spm experiment is enabled" do
    before { Dependabot::Experiments.register(:enable_swift_xcode_spm, true) }
    after { Dependabot::Experiments.register(:enable_swift_xcode_spm, false) }

    describe "#updated_dependency_files" do
      subject(:updated_dependency_files) { updater.updated_dependency_files }

      let(:project_name) { "xcode_project" }
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
      let(:files) do
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

      context "when updating a dependency version" do
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
                  ref: "abc123newrevision",
                  branch: nil
                },
                metadata: {
                  requirement_string: "from: \"2.55.0\""
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
                },
                metadata: {
                  requirement_string: "from: \"2.54.0\""
                }
              }],
              package_manager: "swift",
              metadata: { identity: "swift-nio" }
            )
          ]
        end

        it "returns the updated Package.resolved and project.pbxproj files" do
          expect(updated_dependency_files.length).to eq(2)

          resolved = updated_dependency_files.find { |f| f.name.end_with?("Package.resolved") }
          expect(resolved.name).to eq(
            "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
          )

          pbxproj = updated_dependency_files.find { |f| f.name.end_with?("project.pbxproj") }
          expect(pbxproj.name).to eq("MyApp.xcodeproj/project.pbxproj")
          expect(pbxproj.support_file).to be false
        end

        it "updates the version in the resolved file" do
          resolved = updated_dependency_files.find { |f| f.name.end_with?("Package.resolved") }
          expect(resolved.content).to include('"version" : "2.55.0"')
          expect(resolved.content).not_to include('"version" : "2.54.0"')
        end

        it "updates the minimumVersion in the pbxproj file" do
          pbxproj = updated_dependency_files.find { |f| f.name.end_with?("project.pbxproj") }
          expect(pbxproj.content).to include("minimumVersion = 2.55.0;")
          expect(pbxproj.content).not_to include("minimumVersion = 2.54.0;")
        end

        it "preserves the schema version" do
          resolved = updated_dependency_files.find { |f| f.name.end_with?("Package.resolved") }
          parsed = JSON.parse(resolved.content)
          expect(parsed["version"]).to eq(2)
        end
      end

      context "with workspace-scoped Package.resolved" do
        let(:project_name) { "xcode_workspace" }
        let(:files) do
          [
            Dependabot::DependencyFile.new(
              name: "MyApp.xcworkspace/contents.xcworkspacedata",
              content: fixture("projects", project_name, "MyApp.xcworkspace", "contents.xcworkspacedata"),
              support_file: true
            ),
            Dependabot::DependencyFile.new(
              name: "AppA.xcodeproj/project.pbxproj",
              content: fixture("projects", project_name, "AppA.xcodeproj", "project.pbxproj"),
              support_file: true
            ),
            Dependabot::DependencyFile.new(
              name: "MyApp.xcworkspace/xcshareddata/swiftpm/Package.resolved",
              content: fixture(
                "projects",
                project_name,
                "MyApp.xcworkspace",
                "xcshareddata",
                "swiftpm",
                "Package.resolved"
              )
            )
          ]
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
                file: "AppA.xcodeproj/project.pbxproj",
                source: {
                  type: "git",
                  url: "https://github.com/apple/swift-nio.git",
                  ref: "abc123newrevision",
                  branch: nil
                },
                metadata: {
                  requirement_string: "from: \"2.55.0\""
                }
              }],
              previous_requirements: [{
                requirement: ">= 2.54.0, < 3.0.0",
                groups: ["dependencies"],
                file: "AppA.xcodeproj/project.pbxproj",
                source: {
                  type: "git",
                  url: "https://github.com/apple/swift-nio.git",
                  ref: "1234567890abcdef1234567890abcdef12345678",
                  branch: nil
                },
                metadata: {
                  requirement_string: "from: \"2.54.0\""
                }
              }],
              package_manager: "swift",
              metadata: { identity: "swift-nio" }
            )
          ]
        end

        it "updates workspace Package.resolved and project.pbxproj" do
          expect(updated_dependency_files.length).to eq(2)

          resolved = updated_dependency_files.find { |f| f.name.end_with?("Package.resolved") }
          expect(resolved.name).to eq("MyApp.xcworkspace/xcshareddata/swiftpm/Package.resolved")
          expect(resolved.content).to include('"version" : "2.55.0"')

          pbxproj = updated_dependency_files.find { |f| f.name.end_with?("project.pbxproj") }
          expect(pbxproj.name).to eq("AppA.xcodeproj/project.pbxproj")
          expect(pbxproj.content).to include("minimumVersion = 2.55.0;")
        end
      end

      context "with multiple Xcode projects" do
        let(:project_name) { "xcode_project_multiple" }
        let(:files) do
          [
            Dependabot::DependencyFile.new(
              name: "AppA.xcodeproj/project.pbxproj",
              content: fixture("projects", project_name, "AppA.xcodeproj", "project.pbxproj"),
              support_file: true
            ),
            Dependabot::DependencyFile.new(
              name: "AppA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
              content: fixture(
                "projects",
                project_name,
                "AppA.xcodeproj",
                "project.xcworkspace",
                "xcshareddata",
                "swiftpm",
                "Package.resolved"
              )
            ),
            Dependabot::DependencyFile.new(
              name: "AppB.xcodeproj/project.pbxproj",
              content: fixture("projects", project_name, "AppB.xcodeproj", "project.pbxproj"),
              support_file: true
            ),
            Dependabot::DependencyFile.new(
              name: "AppB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
              content: fixture(
                "projects",
                project_name,
                "AppB.xcodeproj",
                "project.xcworkspace",
                "xcshareddata",
                "swiftpm",
                "Package.resolved"
              )
            )
          ]
        end

        context "when updating dependency in AppA only" do
          let(:dependencies) do
            [
              Dependabot::Dependency.new(
                name: "github.com/apple/swift-nio",
                version: "2.55.0",
                previous_version: "2.54.0",
                requirements: [{
                  requirement: ">= 2.55.0, < 3.0.0",
                  groups: ["dependencies"],
                  file: "AppA.xcodeproj/project.pbxproj",
                  source: {
                    type: "git",
                    url: "https://github.com/apple/swift-nio.git",
                    ref: "newrevision",
                    branch: nil
                  }
                }],
                previous_requirements: [{
                  requirement: ">= 2.54.0, < 3.0.0",
                  groups: ["dependencies"],
                  file: "AppA.xcodeproj/project.pbxproj",
                  source: {
                    type: "git",
                    url: "https://github.com/apple/swift-nio.git",
                    ref: "oldrevision",
                    branch: nil
                  }
                }],
                package_manager: "swift",
                metadata: { identity: "swift-nio" }
              )
            ]
          end

          it "updates AppA's Package.resolved and project.pbxproj" do
            expect(updated_dependency_files.length).to eq(2)
            expect(updated_dependency_files.map(&:name)).to all(include("AppA.xcodeproj"))
          end

          it "does not modify AppB's files" do
            expect(updated_dependency_files.map(&:name)).not_to include(
              a_string_matching(/AppB\.xcodeproj/)
            )
          end
        end
      end

      context "with v1 Package.resolved format" do
        let(:project_name) { "xcode_project_v1_resolved" }
        let(:files) do
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
                  ref: "newrevision",
                  branch: nil
                }
              }],
              package_manager: "swift",
              metadata: { identity: "swift-nio" }
            )
          ]
        end

        it "preserves v1 format while updating" do
          resolved = updated_dependency_files.find { |f| f.name.end_with?("Package.resolved") }
          parsed = JSON.parse(resolved.content)
          expect(parsed["version"]).to eq(1)
          expect(parsed["object"]["pins"].first["state"]["version"]).to eq("2.55.0")
        end

        it "also updates the project.pbxproj" do
          pbxproj = updated_dependency_files.find { |f| f.name.end_with?("project.pbxproj") }
          expect(pbxproj).not_to be_nil
          expect(pbxproj.content).to include("minimumVersion = 2.55.0;")
        end
      end
    end
  end
end
