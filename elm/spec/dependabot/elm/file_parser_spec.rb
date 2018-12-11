# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/elm/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Elm::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [elm_package] }
  let(:elm_package) do
    Dependabot::DependencyFile.new(
      name: "elm-package.json",
      content: fixture("elm_packages", elm_package_fixture_name)
    )
  end
  let(:elm_package_fixture_name) { "one_fixture_to_test_them_all" }
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

    context "with an elm-package.json" do
      let(:files) { [elm_package] }

      its(:length) { is_expected.to eq(5) }

      context "that is not parseable" do
        let(:elm_package_fixture_name) { "bad_json" }

        it "raises a helpful error" do
          expect { parser.parse }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("elm-package.json")
          end
        end
      end

      describe "the parsed dependenency details" do
        subject(:dependency) do
          dependencies.find { |d| d.name == dependency_name }
        end

        context "with <=" do
          let(:dependency_name) { "realWorldElmPackage/withOrEqualsUpperBound" }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "2.0.0 <= v <= 2.2.0",
                file: "elm-package.json",
                groups: [],
                source: nil
              }]
            )
          end

          context "and an exact match" do
            let(:dependency_name) { "realWorldElmPackage/exact" }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to eq("2.0.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "2.0.0 <= v <= 2.0.0",
                  file: "elm-package.json",
                  groups: [],
                  source: nil
                }]
              )
            end
          end
        end

        context "with <" do
          context "with 1.0.1" do
            let(:dependency_name) do
              "realWorldElmPackage/withMinimumUpperBound"
            end

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0 <= v < 1.0.1",
                  file: "elm-package.json",
                  groups: [],
                  source: nil
                }]
              )
            end
          end

          context "with 1.1.0" do
            let(:dependency_name) do
              "realWorldElmPackage/withZeroPatchUpperBound"
            end

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0 <= v < 1.1.0",
                  file: "elm-package.json",
                  groups: [],
                  source: nil
                }]
              )
            end
          end

          # Not testing 1.0.0 because < 1.0.0 is already an invalid constraint.
          # Elm packages start at 1.0.0

          context "with 2.0.0" do
            let(:dependency_name) do
              "realWorldElmPackage/withZeroMinorUpperBound"
            end

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: "1.0.0 <= v < 2.0.0",
                  file: "elm-package.json",
                  groups: [],
                  source: nil
                }]
              )
            end
          end
        end
      end
    end

    context "with an elm.json" do
      let(:files) { [elm_json] }

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

        describe "the parsed dependenency details" do
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
