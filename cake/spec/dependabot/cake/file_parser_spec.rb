# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/cake/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Cake::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [cake_file] }
  let(:cake_file) do
    Dependabot::DependencyFile.new(name: "build.cake", content: cake_file_body)
  end
  let(:cake_file_body) do
    fixture("cake_files", cake_file_fixture_name)
  end
  let(:cake_file_fixture_name) { "valid" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(1) }

    describe "the dependency" do
      subject(:dependency) { dependencies.first }
      let(:expected_requirements) do
        [{
          requirement: "0.4.0",
          groups: [],
          file: "build.cake",
          source: nil,
          metadata: { cake_directive: {
            type: "module",
            scheme: "nuget",
            url: nil,
            query: { package: "Cake.Module", version: "0.4.0" }
          } }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("Cake.Module")
        expect(dependency.version).to eq("0.4.0")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with not supported directive" do
      let(:cake_file_fixture_name) { "not_supported_directive" }
      its(:length) { is_expected.to eq(0) }
    end

    context "with not supported scheme" do
      let(:cake_file_fixture_name) { "not_supported_scheme" }
      its(:length) { is_expected.to eq(0) }
    end

    context "with no package" do
      let(:cake_file_fixture_name) { "no_package" }
      its(:length) { is_expected.to eq(0) }
    end

    context "with no version number" do
      let(:cake_file_fixture_name) { "no_version" }
      its(:length) { is_expected.to eq(0) }
    end

    context "with multiple directive" do
      let(:cake_file_fixture_name) { "multiple_directives" }
      its(:length) { is_expected.to eq(3) }

      describe "the module dependency" do
        subject(:dependency) { dependencies[0] }
        let(:expected_requirements) do
          [{
            requirement: "0.1.0",
            groups: [],
            file: "build.cake",
            source: nil,
            metadata: { cake_directive: {
              type: "module",
              scheme: "nuget",
              url: nil,
              query: { package: "Cake.Module", version: "0.1.0" }
            } }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Cake.Module")
          expect(dependency.version).to eq("0.1.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the addin dependency" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: "1.2.0",
            groups: [],
            file: "build.cake",
            source: nil,
            metadata: { cake_directive: {
              type: "addin",
              scheme: "nuget",
              url: nil,
              query: { package: "Cake.Addin", version: "1.2.0" }
            } }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Cake.Addin")
          expect(dependency.version).to eq("1.2.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the tool dependency" do
        subject(:dependency) { dependencies[2] }
        let(:expected_requirements) do
          [{
            requirement: "2.0.1",
            groups: [],
            file: "build.cake",
            source: nil,
            metadata: { cake_directive: {
              type: "tool",
              scheme: "nuget",
              url: nil,
              query: { package: "Cake.Tool", version: "2.0.1" }
            } }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Cake.Tool")
          expect(dependency.version).to eq("2.0.1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with multiple cake_files" do
      let(:files) { [cake_file, cake_file2] }
      let(:cake_file2) do
        Dependabot::DependencyFile.new(
          name: "tasks.cake",
          content: cake_file2_body2
        )
      end
      let(:cake_file2_body2) { fixture("cake_files", "tasks") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies[0] }
        let(:expected_requirements) do
          [{
            requirement: "0.4.0",
            groups: [],
            file: "build.cake",
            source: nil,
            metadata: { cake_directive: {
              type: "module",
              scheme: "nuget",
              url: nil,
              query: { package: "Cake.Module", version: "0.4.0" }
            } }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Cake.Module")
          expect(dependency.version).to eq("0.4.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: "1.2.0",
            groups: [],
            file: "tasks.cake",
            source: nil,
            metadata: { cake_directive: {
              type: "addin",
              scheme: "nuget",
              url: nil,
              query: { package: "Cake.Addin", version: "1.2.0" }
            } }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Cake.Addin")
          expect(dependency.version).to eq("1.2.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with directive source url" do
      let(:cake_file_fixture_name) { "directive_source_url" }
      its(:length) { is_expected.to eq(1) }

      describe "the dependency" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "10.0.1",
            groups: [],
            file: "build.cake",
            source: nil,
            metadata: { cake_directive: {
              type: "addin",
              scheme: "nuget",
              url: "https://myget.org/f/Cake/",
              query: { package: "Cake.Foo", version: "10.0.1" }
            } }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Cake.Foo")
          expect(dependency.version).to eq("10.0.1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end
  end
end
