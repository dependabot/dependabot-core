# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/opam/file_updater"

RSpec.describe Dependabot::Opam::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: credentials
    )
  end
  let(:credentials) { [] }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "example.opam",
        content: opam_file_content
      )
    ]
  end

  let(:opam_file_content) do
    <<~OPAM
      opam-version: "2.0"
      name: "example"
      version: "1.0.0"
      depends: [
        "ocaml" {>= "4.08.0"}
        "dune" {>= "2.0"}
        "lwt" {>= "5.0.0" & < "6.0.0"}
      ]
    OPAM
  end

  let(:dependencies) do
    [
      Dependabot::Dependency.new(
        name: "lwt",
        version: "5.8.0",
        previous_version: "5.0.0",
        requirements: updated_requirements,
        previous_requirements: previous_requirements,
        package_manager: "opam"
      )
    ]
  end

  let(:previous_requirements) do
    [{
      file: "example.opam",
      requirement: ">= \"5.0.0\" & < \"6.0.0\"",
      groups: [],
      source: nil
    }]
  end

  let(:updated_requirements) do
    [{
      file: "example.opam",
      requirement: ">= \"5.8.0\" & < \"6.0.0\"",
      groups: [],
      source: nil
    }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns an array of updated dependency files" do
      expect(updated_files).to be_a(Array)
      expect(updated_files.length).to eq(1)
    end

    it "updates the opam file with new version constraint" do
      updated_file = updated_files.first
      expect(updated_file.name).to eq("example.opam")
      expect(updated_file.content).to include(">= \"5.8.0\" & < \"6.0.0\"")
      expect(updated_file.content).not_to include(">= \"5.0.0\" & < \"6.0.0\"")
    end

    it "preserves other dependencies unchanged" do
      updated_file = updated_files.first
      expect(updated_file.content).to include("\"ocaml\" {>= \"4.08.0\"}")
      expect(updated_file.content).to include("\"dune\" {>= \"2.0\"}")
    end

    it "preserves file structure and metadata" do
      updated_file = updated_files.first
      expect(updated_file.content).to include("opam-version: \"2.0\"")
      expect(updated_file.content).to include("name: \"example\"")
      expect(updated_file.content).to include("version: \"1.0.0\"")
    end

    context "with simple version constraint" do
      let(:opam_file_content) do
        <<~OPAM
          depends: [
            "dune" {>= "2.0"}
          ]
        OPAM
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "dune",
            version: "3.0.0",
            previous_version: "2.0",
            requirements: [{
              file: "example.opam",
              requirement: ">= \"3.0\"",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "example.opam",
              requirement: ">= \"2.0\"",
              groups: [],
              source: nil
            }],
            package_manager: "opam"
          )
        ]
      end

      it "updates simple constraint" do
        updated_file = updated_files.first
        expect(updated_file.content).to include("\"dune\" { >= \"3.0\" }")
        expect(updated_file.content).not_to include("\"dune\" { >= \"2.0\" }")
      end
    end

    context "with multiple files" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "lib.opam",
            content: lib_content
          ),
          Dependabot::DependencyFile.new(
            name: "test.opam",
            content: test_content
          )
        ]
      end

      let(:lib_content) do
        <<~OPAM
          depends: [
            "lwt" {>= "5.0.0"}
          ]
        OPAM
      end

      let(:test_content) do
        <<~OPAM
          depends: [
            "alcotest" {>= "1.0.0"}
          ]
        OPAM
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "lwt",
            version: "5.8.0",
            requirements: [{
              file: "lib.opam",
              requirement: ">= \"5.8.0\"",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "lib.opam",
              requirement: ">= \"5.0.0\"",
              groups: [],
              source: nil
            }],
            package_manager: "opam"
          )
        ]
      end

      it "updates only the specified file" do
        updated_lib = updated_files.find { |f| f.name == "lib.opam" }
        expect(updated_lib.content).to include("\"lwt\" { >= \"5.8.0\" }")

        updated_test = updated_files.find { |f| f.name == "test.opam" }
        expect(updated_test).to be_nil # test.opam not changed
      end
    end

    context "with exact version constraint" do
      let(:opam_file_content) do
        <<~OPAM
          depends: [
            "base" {= "v0.14.0"}
          ]
        OPAM
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "base",
            version: "v0.15.0",
            requirements: [{
              file: "example.opam",
              requirement: "= \"v0.15.0\"",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "example.opam",
              requirement: "= \"v0.14.0\"",
              groups: [],
              source: nil
            }],
            package_manager: "opam"
          )
        ]
      end

      it "updates exact version" do
        updated_file = updated_files.first
        expect(updated_file.content).to include("\"base\" { = \"v0.15.0\" }")
        expect(updated_file.content).not_to include("\"base\" { = \"v0.14.0\" }")
      end
    end
  end
end
