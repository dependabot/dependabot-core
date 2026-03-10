# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/swift/file_parser/pbxproj_parser"

RSpec.describe Dependabot::Swift::FileParser::PbxprojParser do
  subject(:parser) { described_class.new(pbxproj_file) }

  let(:pbxproj_file) do
    Dependabot::DependencyFile.new(
      name: file_name,
      content: file_content,
      support_file: true
    )
  end

  describe "#parse" do
    context "with upToNextMajorVersion requirement" do
      let(:file_name) { "MyApp.xcodeproj/project.pbxproj" }
      let(:file_content) { fixture("projects", "xcode_project", "MyApp.xcodeproj", "project.pbxproj") }

      it "parses the requirement correctly" do
        reqs = parser.parse
        expect(reqs.length).to eq(1)

        name = reqs.keys.first
        expect(name).to eq("github.com/apple/swift-nio")

        req_info = reqs[name]
        expect(req_info[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(req_info[:requirement_string]).to eq("from: \"2.54.0\"")
        expect(req_info[:kind]).to eq("upToNextMajorVersion")
        expect(req_info[:file]).to eq(file_name)
        expect(req_info[:url]).to eq("https://github.com/apple/swift-nio.git")
      end
    end

    context "with multiple requirement types" do
      let(:file_name) { "MyApp.xcodeproj/project.pbxproj" }
      let(:file_content) { fixture("projects", "xcode_project_multi_req", "MyApp.xcodeproj", "project.pbxproj") }

      it "parses all package references" do
        reqs = parser.parse
        expect(reqs.length).to eq(4)
      end

      it "parses upToNextMajorVersion correctly" do
        req = parser.parse["github.com/apple/swift-nio"]
        expect(req[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(req[:requirement_string]).to eq("from: \"2.54.0\"")
        expect(req[:kind]).to eq("upToNextMajorVersion")
      end

      it "parses upToNextMinorVersion correctly" do
        req = parser.parse["github.com/apple/swift-collections"]
        expect(req[:requirement]).to eq(">= 1.0.0, < 1.1.0")
        expect(req[:requirement_string]).to eq(".upToNextMinor(from: \"1.0.0\")")
        expect(req[:kind]).to eq("upToNextMinorVersion")
      end

      it "parses exactVersion correctly" do
        req = parser.parse["github.com/apple/swift-argument-parser"]
        expect(req[:requirement]).to eq("= 1.2.0")
        expect(req[:requirement_string]).to eq("exact: \"1.2.0\"")
        expect(req[:kind]).to eq("exactVersion")
      end

      it "parses versionRange correctly" do
        req = parser.parse["github.com/apple/swift-log"]
        expect(req[:requirement]).to eq(">= 1.4.0, < 2.0.0")
        expect(req[:requirement_string]).to eq("\"1.4.0\"..<\"2.0.0\"")
        expect(req[:kind]).to eq("versionRange")
      end
    end

    context "with revision requirement" do
      let(:file_name) { "MyApp.xcodeproj/project.pbxproj" }
      let(:file_content) do
        fixture("projects", "xcode_project_revision_only", "MyApp.xcodeproj", "project.pbxproj")
      end

      it "returns nil requirement for revision-pinned packages" do
        reqs = parser.parse
        expect(reqs.length).to eq(1)

        req = reqs["github.com/apple/swift-nio"]
        expect(req[:requirement]).to be_nil
        expect(req[:requirement_string]).to be_nil
        expect(req[:kind]).to eq("revision")
        expect(req[:revision]).to eq("6213ba7a06febe8fef60563a4a7d26a4085783cf")
      end
    end

    context "with no XCRemoteSwiftPackageReference entries" do
      let(:file_name) { "MyApp.xcodeproj/project.pbxproj" }
      let(:file_content) do
        fixture("projects", "xcode_project_empty_pins", "MyApp.xcodeproj", "project.pbxproj")
      end

      it "returns an empty hash" do
        expect(parser.parse).to be_empty
      end
    end

    context "with nil content" do
      let(:file_name) { "MyApp.xcodeproj/project.pbxproj" }
      let(:file_content) { nil }

      it "returns an empty hash" do
        expect(parser.parse).to be_empty
      end
    end

    context "with branch requirement" do
      let(:file_name) { "MyApp.xcodeproj/project.pbxproj" }
      let(:file_content) do
        <<~PBXPROJ
          // !$*UTF8*$!
          {
          	archiveVersion = 1;
          	objects = {
          		A1B2C3D4E5F60001 /* XCRemoteSwiftPackageReference "swift-nio" */ = {
          			isa = XCRemoteSwiftPackageReference;
          			repositoryURL = "https://github.com/apple/swift-nio.git";
          			requirement = {
          				kind = branch;
          				branch = main;
          			};
          		};
          	};
          	rootObject = A1B2C3D4E5F60000;
          }
        PBXPROJ
      end

      it "returns nil requirement with branch info" do
        req = parser.parse["github.com/apple/swift-nio"]
        expect(req[:requirement]).to be_nil
        expect(req[:kind]).to eq("branch")
        expect(req[:branch]).to eq("main")
      end
    end
  end
end
