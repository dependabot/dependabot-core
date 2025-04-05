# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/pub/file_parser"
require "dependabot/pub/version"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Pub::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: files,
      source: source
    )
  end

  let(:directory) { "/" }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: directory) }
  let(:files) { [] }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with a pinned dependency" do
      let(:files) { project_dependency_files("pinned_version") }

      specify { expect(dependencies.length).to eq(1) }
      specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the dependency" do
        expect(dependencies[0].name).to eq("retry")
        expect(dependencies[0].version).to eq("2.0.0")
        expect(dependencies[0].requirements).to eq([{
          requirement: "2.0.0",
          groups: ["direct"],
          file: "pubspec.yaml",
          source: { "description" => { "name" => "retry", "url" => "https://pub.dev" }, "type" => "hosted" }
        }])
      end
    end

    context "with several dependencies" do
      let(:files) { project_dependency_files("constraints") }

      specify { expect(dependencies.length).to eq(49) }
      specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the retry (direct) dependency" do
        dep = dependencies.find { |d| d.name == "retry" }
        expect(dep.version).to eq("2.0.0")
        expect(dep.requirements).to eq([{
          requirement: "^2.0.0",
          groups: ["direct"],
          file: "pubspec.yaml",
          source: { "description" => { "name" => "retry", "url" => "https://pub.dev" }, "type" => "hosted" }
        }])
      end

      it "has the right details for the test (dev) dependency" do
        dep = dependencies.find { |d| d.name == "test" }
        expect(dep.version).to eq("1.17.12")
        expect(dep.requirements).to eq([{
          requirement: ">=1.17.10 <=1.17.12",
          groups: ["dev"],
          file: "pubspec.yaml",
          source: { "description" => { "name" => "test", "url" => "https://pub.dev" }, "type" => "hosted" }
        }])
      end

      it "has the right details for the test_core (transitive) dependency" do
        dep = dependencies.find { |d| d.name == "test_core" }
        expect(dep.version).to eq("0.4.2")
        expect(dep.requirements).to eq([])
      end
    end

    context "with a broken pubspec.yaml" do
      let(:files) { project_dependency_files("broken_pubspec") }

      it "raises a helpful error" do
        expect { dependencies }.to raise_error(Dependabot::DependabotError) do |error|
          expect(error.message).to start_with("dependency_services failed: " \
                                              "Error on line 3, column 1 of pubspec.yaml: Unexpected end of file.")
        end
      end
    end
  end
end
