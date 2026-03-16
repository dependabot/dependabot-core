# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/swift/file_parser/xcode_spm_resolver"

RSpec.describe Dependabot::Swift::FileParser::XcodeSpmResolver do
  subject(:resolver) do
    described_class.new(
      xcode_resolved_files: xcode_resolved_files,
      pbxproj_files: pbxproj_files
    )
  end

  let(:xcode_resolved_files) { [] }
  let(:pbxproj_files) { [] }

  describe "#parse" do
    context "with a single Xcode project (v2 Package.resolved)" do
      let(:project_name) { "xcode_project" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses dependencies" do
        deps = resolver.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
        expect(dep.package_manager).to eq("swift")
      end

      it "enriches dependencies with pbxproj requirements" do
        dep = resolver.parse.first
        req = dep.requirements.first

        expect(req[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(req[:file]).to eq("MyApp.xcodeproj/project.pbxproj")
        expect(req[:metadata][:requirement_string]).to eq("from: \"2.54.0\"")
      end

      it "sets correct source info" do
        dep = resolver.parse.first
        source = dep.requirements.first[:source]

        expect(source[:type]).to eq("git")
        expect(source[:url]).to eq("https://github.com/apple/swift-nio.git")
        expect(source[:ref]).to eq("2.54.0")
      end
    end

    context "with multiple .xcodeproj directories" do
      let(:project_name) { "xcode_project_multiple" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "AppA.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "AppA.xcodeproj", "project.pbxproj"),
            support_file: true
          ),
          Dependabot::DependencyFile.new(
            name: "AppB.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "AppB.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses dependencies from all resolved files" do
        deps = resolver.parse
        names = deps.map(&:name)

        expect(names).to include("github.com/apple/swift-nio")
        expect(names).to include("github.com/apple/swift-collections")
      end

      it "associates requirements with correct pbxproj files" do
        deps = resolver.parse
        nio = deps.find { |d| d.name == "github.com/apple/swift-nio" }
        collections = deps.find { |d| d.name == "github.com/apple/swift-collections" }

        expect(nio.requirements.first[:file]).to eq("AppA.xcodeproj/project.pbxproj")
        expect(collections.requirements.first[:file]).to eq("AppB.xcodeproj/project.pbxproj")
      end
    end

    context "with workspace-scoped Package.resolved and sibling project" do
      let(:project_name) { "xcode_workspace" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "AppA.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "AppA.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses and enriches dependencies using available pbxproj requirements" do
        dep = resolver.parse.first

        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.requirements.first[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(dep.requirements.first[:file]).to eq("AppA.xcodeproj/project.pbxproj")
      end
    end

    context "with multiple dependencies and requirement types" do
      let(:project_name) { "xcode_project_multi_req" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses all dependencies" do
        deps = resolver.parse
        expect(deps.length).to eq(4)

        names = deps.map(&:name)
        expect(names).to contain_exactly(
          "github.com/apple/swift-nio",
          "github.com/apple/swift-collections",
          "github.com/apple/swift-argument-parser",
          "github.com/apple/swift-log"
        )
      end

      it "applies correct requirement types from pbxproj" do
        deps = resolver.parse
        nio = deps.find { |d| d.name == "github.com/apple/swift-nio" }
        collections = deps.find { |d| d.name == "github.com/apple/swift-collections" }
        parser_dep = deps.find { |d| d.name == "github.com/apple/swift-argument-parser" }
        log = deps.find { |d| d.name == "github.com/apple/swift-log" }

        expect(nio.requirements.first[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(collections.requirements.first[:requirement]).to eq(">= 1.0.0, < 1.1.0")
        expect(parser_dep.requirements.first[:requirement]).to eq("= 1.2.0")
        expect(log.requirements.first[:requirement]).to eq(">= 1.4.0, < 2.0.0")
      end
    end

    context "with no pbxproj file (only Package.resolved)" do
      let(:project_name) { "xcode_project" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) { [] }

      it "parses dependencies without requirement enrichment" do
        deps = resolver.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
        expect(dep.requirements.first[:requirement]).to eq("= 2.54.0")
      end
    end

    context "with empty pins" do
      let(:project_name) { "xcode_project_empty_pins" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "returns an empty dependency list" do
        expect(resolver.parse).to be_empty
      end
    end

    context "with revision-only pin (no version)" do
      let(:project_name) { "xcode_project_revision_only" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses with nil version" do
        dep = resolver.parse.first
        expect(dep.version).to be_nil
      end

      it "records revision in source ref" do
        dep = resolver.parse.first
        source = dep.requirements.first[:source]
        expect(source[:ref]).to eq("6213ba7a06febe8fef60563a4a7d26a4085783cf")
      end
    end

    context "with v1 Package.resolved" do
      let(:project_name) { "xcode_project_v1_resolved" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses v1 format dependencies" do
        deps = resolver.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
      end
    end

    context "with v3 Package.resolved" do
      let(:project_name) { "xcode_project_v3_resolved" }
      let(:xcode_resolved_files) do
        [
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
      let(:pbxproj_files) do
        [
          Dependabot::DependencyFile.new(
            name: "MyApp.xcodeproj/project.pbxproj",
            content: fixture("projects", project_name, "MyApp.xcodeproj", "project.pbxproj"),
            support_file: true
          )
        ]
      end

      it "parses v3 format dependencies" do
        deps = resolver.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
      end
    end

    context "with no resolved files" do
      let(:xcode_resolved_files) { [] }
      let(:pbxproj_files) { [] }

      it "returns an empty dependency list" do
        expect(resolver.parse).to be_empty
      end
    end
  end
end
