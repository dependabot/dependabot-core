# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/swift/file_parser/xcproj_parser"

RSpec.describe Dependabot::Swift::FileParser::XcprojParser do
  extend T::Sig

  sig { returns(Dependabot::Swift::FileParser::XcprojParser) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:parser) { described_class.new(xcproj_file) }

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(String) }
  let(:file_name) { "MyApp.xcodeproj/project.xcproj" }

  sig { returns(String) }
  let(:file_content) { fixture("projects", "xcode_project_xcproj", "MyApp.xcodeproj", "project.xcproj") }

  sig { returns(Dependabot::DependencyFile) }
  let(:xcproj_file) do
    Dependabot::DependencyFile.new(
      name: file_name,
      content: file_content,
      support_file: true
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#parse" do
    context "with an upToNextMajorVersion requirement" do
      it "parses the requirement in the same shape as PbxprojParser" do
        reqs = parser.parse
        expect(reqs.keys).to eq(["github.com/apple/swift-nio"])

        req_info = T.must(reqs["github.com/apple/swift-nio"])
        expect(req_info[:requirement]).to eq(">= 2.54.0, < 3.0.0")
        expect(req_info[:requirement_string]).to eq("from: \"2.54.0\"")
        expect(req_info[:kind]).to eq("upToNextMajorVersion")
        expect(req_info[:file]).to eq(file_name)
        expect(req_info[:url]).to eq("https://github.com/apple/swift-nio.git")
      end
    end

    context "with every requirement kind" do
      sig { returns(String) }
      let(:file_content) do
        fixture("projects", "xcode_project_xcproj_multi_req", "MyApp.xcodeproj", "project.xcproj")
      end

      it "parses all remote packages and skips local ones" do
        expect(parser.parse.keys).to contain_exactly(
          "github.com/apple/swift-nio",
          "github.com/apple/swift-collections",
          "github.com/apple/swift-argument-parser",
          "github.com/apple/swift-log",
          "github.com/swiftlang/swift-syntax",
          "github.com/apple/swift-algorithms",
          "github.com/apple/swift-numerics"
        )
      end

      it "parses up-to-next-minor-version" do
        req = T.must(parser.parse["github.com/apple/swift-collections"])
        expect(req[:requirement]).to eq(">= 1.0.0, < 1.1.0")
        expect(req[:requirement_string]).to eq(".upToNextMinor(from: \"1.0.0\")")
        expect(req[:kind]).to eq("upToNextMinorVersion")
      end

      it "parses version as an exact requirement" do
        req = T.must(parser.parse["github.com/apple/swift-argument-parser"])
        expect(req[:requirement]).to eq("= 1.2.0")
        expect(req[:requirement_string]).to eq("exact: \"1.2.0\"")
        expect(req[:kind]).to eq("exactVersion")
      end

      it "parses version-range" do
        req = T.must(parser.parse["github.com/apple/swift-log"])
        expect(req[:requirement]).to eq(">= 1.4.0, < 2.0.0")
        expect(req[:requirement_string]).to eq("\"1.4.0\"..<\"2.0.0\"")
        expect(req[:kind]).to eq("versionRange")
      end

      it "parses version-range-min and version-range-max" do
        req = T.must(parser.parse["github.com/swiftlang/swift-syntax"])
        expect(req[:requirement_string]).to eq("\"600.0.0-prerelease-2024-06-12\"..<\"601.0.0\"")
        expect(req[:kind]).to eq("versionRange")
      end

      it "parses branch" do
        req = T.must(parser.parse["github.com/apple/swift-algorithms"])
        expect(req[:requirement]).to be_nil
        expect(req[:kind]).to eq("branch")
        expect(req[:branch]).to eq("main")
      end

      it "parses revision" do
        req = T.must(parser.parse["github.com/apple/swift-numerics"])
        expect(req[:requirement]).to be_nil
        expect(req[:kind]).to eq("revision")
        expect(req[:revision]).to eq("0a5bc04095a675662cf24757cc0640aa2204253b")
      end
    end

    context "with a remote package without a version constraint" do
      sig { returns(String) }
      let(:file_content) do
        <<~JSON
          {
            "packages": [
              { "kind": "remote", "repository": "https://github.com/apple/swift-nio.git" },
            ],
          }
        JSON
      end

      it "skips the package" do
        expect(parser.parse).to eq({})
      end
    end

    context "without packages" do
      sig { returns(String) }
      let(:file_content) { "{\n  \"default-configuration\": \"Release\",\n}\n" }

      it "returns an empty hash" do
        expect(parser.parse).to eq({})
      end
    end

    context "with invalid JSON" do
      sig { returns(String) }
      let(:file_content) { "{ \"packages\": [" }

      it "raises a DependencyFileNotParseable error" do
        expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.file_path).to eq(file_name)
        end
      end
    end
  end
end
