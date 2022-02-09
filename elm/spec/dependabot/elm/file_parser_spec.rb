# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/elm/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Elm::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [elm_json] }
  let(:elm_json) do
    Dependabot::DependencyFile.new(
      name: "elm.json",
      content: fixture("elm_jsons", elm_json_fixture_name)
    )
  end
  let(:elm_json_fixture_name) { "app.json" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "NoRedInk/noredink-ui",
      directory: "/"
    )
  end

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with an elm.json" do
      context "that is not parseable" do
        let(:elm_json_fixture_name) { "bad_json.json" }

        it "raises a helpful error" do
          expect { parser.parse }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("elm.json")
          end
        end
      end

      context "for an application" do
        let(:elm_json_fixture_name) { "app.json" }

        its(:length) { is_expected.to eq(13) }

        describe "top level dependencies" do
          subject { dependencies.select(&:top_level?) }
          its(:length) { is_expected.to eq(10) }
        end

        describe "the parsed dependency details" do
          subject(:dependency) do
            dependencies.find { |d| d.name == dependency_name }
          end

          context "a direct runtime dependency" do
            let(:dependency_name) { "elm/html" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to eq("1.0.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0",
                  file: "elm.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          context "an indirect runtime dependency" do
            let(:dependency_name) { "elm/parser" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to eq("1.0.0")
              expect(dependency.requirements).to eq([])
            end
          end

          context "a test dependency" do
            let(:dependency_name) { "elm/regex" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to eq("1.0.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0",
                  file: "elm.json",
                  groups: ["test-dependencies"],
                  source: nil
                }]
              )
            end
          end
        end
      end

      context "for a package" do
        let(:elm_json_fixture_name) { "package.json" }

        its(:length) { is_expected.to eq(4) }

        describe "the parsed dependency details" do
          subject(:dependency) do
            dependencies.find { |d| d.name == dependency_name }
          end

          context "an indirect runtime dependency" do
            let(:dependency_name) { "elm/json" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0 <= v < 2.0.0",
                  file: "elm.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          context "a test dependency" do
            let(:dependency_name) { "elm/regex" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0 <= v < 2.0.0",
                  file: "elm.json",
                  groups: ["test-dependencies"],
                  source: nil
                }]
              )
            end
          end
        end
      end
    end
  end
end
