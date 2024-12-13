# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/elm/file_parser"
require "dependabot/elm/package_manager"
require "dependabot/elm/language"

require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Elm::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "NoRedInk/noredink-ui",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:elm_json_fixture_name) { "app.json" }
  let(:elm_json) do
    Dependabot::DependencyFile.new(
      name: "elm.json",
      content: fixture("elm_jsons", elm_json_fixture_name)
    )
  end
  let(:files) { [elm_json] }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with an elm.json" do
      context "when not parseable" do
        let(:elm_json_fixture_name) { "bad_json.json" }

        it "raises a helpful error" do
          expect { parser.parse }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("elm.json")
          end
        end
      end

      context "when dealing with an application" do
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

          context "when dealing with a direct runtime dependency" do
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

          context "when dealing with an indirect runtime dependency" do
            let(:dependency_name) { "elm/parser" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to eq("1.0.0")
              expect(dependency.requirements).to eq([])
            end
          end

          context "when dealing with a test dependency" do
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

      context "when dealing with a package" do
        let(:elm_json_fixture_name) { "package.json" }

        its(:length) { is_expected.to eq(4) }

        describe "the parsed dependency details" do
          subject(:dependency) do
            dependencies.find { |d| d.name == dependency_name }
          end

          context "when dealing with an indirect runtime dependency" do
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

          context "when dealing with a test dependency" do
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

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    describe "package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "returns the correct package manager version" do
        expect(package_manager.version.to_s).to eq("0.19.0")
      end

      it "returns the correct package manager requirement" do
        expect(package_manager.requirement.to_s).to eq("= 0.19.0")
      end
    end

    describe "language" do
      subject(:language) { ecosystem.language }

      context "when elm_version is present" do
        let(:elm_json_fixture_name) { "elm_requirement_fixture.json" }

        it "returns the correct language version" do
          expect(language.version.to_s).to eq("0.19.1")
        end

        it "returns the correct language requirement" do
          expect(language.requirement.to_s).to eq("<= 0.19.1")
        end
      end

      context "when elm_version is missing" do
        let(:elm_json_fixture_name) { "missing_version.json" }

        it "returns nil for the language" do
          expect(language.requirement).to be_nil
        end
      end
    end
  end

  describe "#elm_requirement" do
    subject(:elm_requirement) { parser.send(:elm_requirement) }

    context "when elm requirement is present" do
      let(:elm_json_fixture_name) { "elm_requirement_fixture.json" }

      it "extracts the elm requirement from the parsed JSON" do
        expect(elm_requirement.to_s).to eq("<= 0.19.1")
      end
    end

    context "when elm requirement is missing" do
      let(:elm_json_fixture_name) { "missing_version.json" }

      it "returns nil" do
        expect(elm_requirement).to be_nil
      end
    end
  end

  describe "#extract_version_requirement" do
    subject(:version_requirement) { parser.send(:extract_version_requirement, "elm-version") }

    context "when the field exists" do
      let(:elm_json_fixture_name) { "elm_requirement_fixture.json" }

      it "returns a Requirement object with >= 0.19.0" do
        expect(version_requirement.to_s).to eq("<= 0.19.1")
      end
    end

    context "when the field does not exist" do
      let(:elm_json_fixture_name) { "missing_version.json" }

      it "returns nil" do
        expect(version_requirement).to be_nil
      end
    end
  end
end
