# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/swift/file_parser/package_resolved_parser"

RSpec.describe Dependabot::Swift::FileParser::PackageResolvedParser do
  subject(:parser) { described_class.new(resolved_file) }

  let(:resolved_file) do
    Dependabot::DependencyFile.new(
      name: file_name,
      content: file_content
    )
  end

  describe "#parse" do
    context "with v2 schema" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "parses dependencies correctly" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
        expect(dep.package_manager).to eq("swift")
        expect(dep.metadata).to eq({ identity: "swift-nio" })
      end

      it "sets correct requirements" do
        dep = parser.parse.first
        req = dep.requirements.first

        expect(req[:requirement]).to eq("= 2.54.0")
        expect(req[:groups]).to eq(["dependencies"])
        expect(req[:file]).to eq(file_name)
        expect(req[:source]).to eq(
          {
            type: "git",
            url: "https://github.com/apple/swift-nio.git",
            ref: "2.54.0",
            branch: nil
          }
        )
      end
    end

    context "with v1 schema" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_v1_resolved",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "parses dependencies correctly" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
        expect(dep.package_manager).to eq("swift")
        expect(dep.metadata).to eq({ identity: "swift-nio" })
      end

      it "normalizes v1 identity from package name" do
        dep = parser.parse.first
        # v1 uses "package" field, lowercased for identity
        expect(dep.metadata[:identity]).to eq("swift-nio")
      end
    end

    context "with v3 schema" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_v3_resolved",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "parses dependencies correctly (same as v2 structure)" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to eq("2.54.0")
      end
    end

    context "with revision-only pin (no version)" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_revision_only",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "parses with nil version" do
        deps = parser.parse
        expect(deps.length).to eq(1)

        dep = deps.first
        expect(dep.name).to eq("github.com/apple/swift-nio")
        expect(dep.version).to be_nil
      end

      it "uses revision as ref in source" do
        dep = parser.parse.first
        source = dep.requirements.first[:source]

        expect(source[:ref]).to eq("6213ba7a06febe8fef60563a4a7d26a4085783cf")
        expect(source[:branch]).to be_nil
      end

      it "sets requirement to nil for revision-only pins" do
        dep = parser.parse.first
        expect(dep.requirements.first[:requirement]).to be_nil
      end
    end

    context "with multiple dependencies" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_multi_req",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "parses all dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(4)

        names = deps.map(&:name)
        expect(names).to contain_exactly(
          "github.com/apple/swift-nio",
          "github.com/apple/swift-collections",
          "github.com/apple/swift-argument-parser",
          "github.com/apple/swift-log"
        )
      end
    end

    context "with empty pins array" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_empty_pins",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "returns an empty array" do
        expect(parser.parse).to be_empty
      end
    end

    context "with invalid JSON" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_invalid_json",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "raises DependencyFileNotParseable with file path" do
        expect { parser.parse }.to raise_error(
          Dependabot::DependencyFileNotParseable
        ) do |error|
          expect(error.file_path).to eq(file_name)
          expect(error.message).to include("not valid JSON")
        end
      end
    end

    context "with unknown schema version" do
      let(:file_name) { "MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" }
      let(:file_content) do
        fixture(
          "projects",
          "xcode_project_unknown_schema",
          "MyApp.xcodeproj",
          "project.xcworkspace",
          "xcshareddata",
          "swiftpm",
          "Package.resolved"
        )
      end

      it "raises DependencyFileNotParseable with schema info" do
        expect { parser.parse }.to raise_error(
          Dependabot::DependencyFileNotParseable
        ) do |error|
          expect(error.file_path).to eq(file_name)
          expect(error.message).to include("unsupported schema version")
          expect(error.message).to include("99")
        end
      end
    end

    context "with existing v1 fixture (ReactiveCocoa)" do
      let(:file_name) { "Package.resolved" }
      let(:file_content) { fixture("projects", "ReactiveCocoa", "Package.resolved") }

      it "parses all v1 dependencies" do
        deps = parser.parse
        expect(deps.length).to eq(5)

        names = deps.map(&:name)
        expect(names).to include("github.com/quick/quick")
        expect(names).to include("github.com/quick/nimble")
        expect(names).to include("github.com/reactivecocoa/reactiveswift")
      end

      it "normalizes URLs correctly" do
        quick_dep = parser.parse.find { |d| d.metadata[:identity] == "quick" }
        expect(quick_dep.name).to eq("github.com/quick/quick")
        expect(quick_dep.requirements.first[:source][:url]).to eq("https://github.com/Quick/Quick.git")
      end
    end

    context "with SCP-style URL in pin" do
      let(:file_name) { "Package.resolved" }
      let(:file_content) do
        <<~JSON
          {
            "pins": [
              {
                "identity": "my-package",
                "kind": "remoteSourceControl",
                "location": "git@github.com:owner/my-package.git",
                "state": { "revision": "abc123", "version": "1.0.0" }
              }
            ],
            "version": 2
          }
        JSON
      end

      it "normalizes SCP URLs to HTTPS" do
        dep = parser.parse.first
        expect(dep.name).to eq("github.com/owner/my-package")
        expect(dep.requirements.first[:source][:url]).to eq("https://github.com/owner/my-package.git")
      end
    end
  end
end
