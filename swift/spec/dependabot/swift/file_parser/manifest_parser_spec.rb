# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency_requirement"
require "dependabot/swift/file_parser/manifest_parser"

RSpec.describe Dependabot::Swift::FileParser::ManifestParser do
  subject(:manifest_parser) { described_class.new(manifest, requirement: requirement) }

  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Package.swift", content: content)
  end
  let(:url) { "https://github.com/example/example" }
  let(:requirement) do
    Dependabot::DependencyRequirement.create(
      source: { type: "git", url: url }
    )
  end

  describe "#requirements" do
    subject(:requirements) { manifest_parser.requirements }

    context "with a single-line declaration and additional arguments" do
      let(:content) do
        <<~SWIFT
          let package = Package(
            name: "example",
            dependencies: [
              .package(url: "#{url}", .upToNextMajor(from: "1.0.0"), traits: [])
            ]
          )
        SWIFT
      end

      it "parses the requirement" do
        expect(requirements.length).to eq(1)
        expect(requirements.first[:requirement]).to eq(">= 1.0.0, < 2.0.0")
        expect(requirements.first[:metadata][:requirement_string])
          .to eq(".upToNextMajor(from: \"1.0.0\"), traits: []")
        expect(requirements.first[:metadata][:declaration_string])
          .to eq(".package(url: \"#{url}\", .upToNextMajor(from: \"1.0.0\"), traits: [])")
      end
    end

    context "when the closing parenthesis is on a later line than the requirement" do
      context "with an .upToNextMajor requirement followed by a trailing argument" do
        let(:content) do
          <<~SWIFT
            let package = Package(
              name: "example",
              dependencies: [
                .package(
                  url: "#{url}",
                  .upToNextMajor(from: "1.0.0"),
                  traits: []
                )
              ]
            )
          SWIFT
        end

        it "parses the requirement" do
          expect(requirements.length).to eq(1)
          expect(requirements.first[:requirement]).to eq(">= 1.0.0, < 2.0.0")
          expect(requirements.first[:metadata][:requirement_string]).to eq(".upToNextMajor(from: \"1.0.0\"),")
        end
      end

      context "with a from: requirement followed by a trailing argument" do
        let(:content) do
          <<~SWIFT
            let package = Package(
              name: "example",
              dependencies: [
                .package(
                  url: "#{url}",
                  from: "1.0.0",
                  traits: []
                )
              ]
            )
          SWIFT
        end

        it "parses the requirement" do
          expect(requirements.length).to eq(1)
          expect(requirements.first[:requirement]).to eq(">= 1.0.0, < 2.0.0")
          expect(requirements.first[:metadata][:requirement_string]).to eq("from: \"1.0.0\",")
        end
      end

      context "with a range requirement followed by a trailing argument" do
        let(:content) do
          <<~SWIFT
            let package = Package(
              name: "example",
              dependencies: [
                .package(
                  url: "#{url}",
                  "1.0.0"..<"2.0.0",
                  traits: []
                )
              ]
            )
          SWIFT
        end

        it "parses the requirement" do
          expect(requirements.length).to eq(1)
          expect(requirements.first[:requirement]).to eq(">= 1.0.0, < 2.0.0")
          expect(requirements.first[:metadata][:requirement_string]).to eq("\"1.0.0\"..<\"2.0.0\",")
        end
      end

      context "with an exact: requirement followed by a trailing argument" do
        let(:content) do
          <<~SWIFT
            let package = Package(
              name: "example",
              dependencies: [
                .package(
                  url: "#{url}",
                  exact: "1.0.0",
                  traits: []
                )
              ]
            )
          SWIFT
        end

        it "parses the requirement" do
          expect(requirements.length).to eq(1)
          expect(requirements.first[:requirement]).to eq("= 1.0.0")
          expect(requirements.first[:metadata][:requirement_string]).to eq("exact: \"1.0.0\",")
        end
      end

      context "with a trailing comma after the final labeled argument" do
        let(:content) do
          <<~SWIFT
            let package = Package(
              name: "example",
              dependencies: [
                .package(
                  url: "#{url}",
                  .upToNextMajor(from: "1.0.0"),
                  traits: [],
                )
              ]
            )
          SWIFT
        end

        it "parses the requirement" do
          expect(requirements.length).to eq(1)
          expect(requirements.first[:requirement]).to eq(">= 1.0.0, < 2.0.0")
          expect(requirements.first[:metadata][:requirement_string]).to eq(".upToNextMajor(from: \"1.0.0\"),")
        end
      end
    end

    context "with sibling declarations on their own lines" do
      let(:content) do
        <<~SWIFT
          let package = Package(
            name: "example",
            dependencies: [
              .package(url: "#{url}", "0.1.0"..<"0.1.2"),
              .package(url: "https://github.com/other/other", from: "2.0.0")
            ]
          )
        SWIFT
      end

      it "does not merge sibling declarations" do
        expect(requirements.length).to eq(1)
        expect(requirements.first[:metadata][:declaration_string])
          .to eq(".package(url: \"#{url}\", \"0.1.0\"..<\"0.1.2\")")
        expect(requirements.first[:metadata][:requirement_string]).to eq("\"0.1.0\"..<\"0.1.2\"")
      end
    end
  end
end
