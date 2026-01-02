# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/opam/file_parser"

RSpec.describe Dependabot::Opam::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a simple opam file" do
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

      it "returns the correct number of dependencies" do
        expect(dependencies.length).to eq(3)
      end

      describe "the first dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "ocaml" } }

        it "has the correct details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ocaml")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: ">= 4.08.0",
              groups: [],
              source: nil,
              file: "example.opam"
            }]
          )
          expect(dependency.package_manager).to eq("opam")
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "dune" } }

        it "has the correct details" do
          expect(dependency.name).to eq("dune")
          expect(dependency.requirements).to eq(
            [{
              requirement: ">= 2.0",
              groups: [],
              source: nil,
              file: "example.opam"
            }]
          )
        end
      end

      describe "the third dependency with compound constraint" do
        subject(:dependency) { dependencies.find { |d| d.name == "lwt" } }

        it "has the correct details" do
          expect(dependency.name).to eq("lwt")
          expect(dependency.requirements).to eq(
            [{
              requirement: ">= 5.0.0 & < 6.0.0",
              groups: [],
              source: nil,
              file: "example.opam"
            }]
          )
        end
      end
    end

    context "with optional dependencies (depopts)" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.opam",
            content: opam_file_content
          )
        ]
      end

      let(:opam_file_content) do
        <<~OPAM
          opam-version: "2.0"
          depends: [
            "dune" {>= "2.0"}
          ]
          depopts: [
            "async" {>= "v0.14"}
          ]
        OPAM
      end

      it "parses both depends and depopts" do
        expect(dependencies.length).to eq(2)
      end

      it "marks optional dependencies with metadata" do
        async_dep = dependencies.find { |d| d.name == "async" }
        expect(async_dep.metadata).to eq({ optional: "true" })
      end

      it "regular dependencies have no optional metadata" do
        dune_dep = dependencies.find { |d| d.name == "dune" }
        expect(dune_dep.metadata).to eq({})
      end
    end

    context "with no version constraints" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "test.opam",
            content: opam_file_content
          )
        ]
      end

      let(:opam_file_content) do
        <<~OPAM
          depends: [
            "base"
            "stdio"
          ]
        OPAM
      end

      it "returns dependencies with empty requirements" do
        expect(dependencies.length).to eq(2)

        base_dep = dependencies.find { |d| d.name == "base" }
        expect(base_dep.requirements).to eq([])
      end
    end

    context "with multiple opam files" do
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
            "dune" {>= "2.0"}
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

      it "parses dependencies from all opam files" do
        expect(dependencies.length).to eq(2)
        expect(dependencies.map(&:name)).to contain_exactly("dune", "alcotest")
      end

      it "tracks which file each dependency came from" do
        dune_dep = dependencies.find { |d| d.name == "dune" }
        expect(dune_dep.requirements.first[:file]).to eq("lib.opam")

        alcotest_dep = dependencies.find { |d| d.name == "alcotest" }
        expect(alcotest_dep.requirements.first[:file]).to eq("test.opam")
      end
    end
  end
end
