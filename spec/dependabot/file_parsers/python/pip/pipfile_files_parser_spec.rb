# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/python/pip/pipfile_files_parser"

RSpec.describe Dependabot::FileParsers::Python::Pip::PipfileFilesParser do
  let(:parser) { described_class.new(dependency_files: files) }
  let(:files) { [pipfile, lockfile] }

  let(:pipfile) do
    Dependabot::DependencyFile.new(name: "Pipfile", content: pipfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Pipfile.lock", content: lockfile_body)
  end
  let(:pipfile_body) { fixture("python", "pipfiles", pipfile_fixture_name) }
  let(:lockfile_body) do
    fixture("python", "lockfiles", lockfile_fixture_name)
  end
  let(:pipfile_fixture_name) { "version_not_specified" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }

  describe "dependency_set" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    its(:length) { is_expected.to eq(7) }

    describe "top level dependencies" do
      subject(:dependencies) do
        parser.dependency_set.dependencies.select(&:top_level?)
      end
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        it { is_expected.to be_production }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    describe "sub-dependencies" do
      subject(:dependencies) do
        parser.dependency_set.dependencies.reject(&:top_level?)
      end
      its(:length) { is_expected.to eq(5) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("certifi") }
        its(:version) { is_expected.to eq("2017.11.5") }
        its(:requirements) { is_expected.to eq([]) }
      end
    end

    context "with a version specified" do
      let(:pipfile_fixture_name) { "exact_version" }
      let(:lockfile_fixture_name) { "exact_version.lock" }

      its(:length) { is_expected.to eq(11) }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(2) }

        describe "the last dependency" do
          subject { dependencies.last }
          let(:expected_requirements) do
            [{
              requirement: "==3.4.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("pytest") }
          its(:version) { is_expected.to eq("3.4.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end

      context "using arbitrary equality" do
        let(:pipfile_fixture_name) { "arbitrary_equality" }
        let(:lockfile_fixture_name) { "arbitrary_equality.lock" }

        describe "top level dependencies" do
          subject(:dependencies) do
            parser.dependency_set.dependencies.select(&:top_level?)
          end

          describe "the last dependency" do
            subject { dependencies.last }
            let(:expected_requirements) do
              [{
                requirement: "===3.4.0",
                file: "Pipfile",
                source: nil,
                groups: ["develop"]
              }]
            end

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("pytest") }
            its(:version) { is_expected.to eq("3.4.0") }
            its(:requirements) { is_expected.to eq(expected_requirements) }
          end
        end
      end
    end

    context "with only dev dependencies" do
      let(:pipfile_fixture_name) { "only_dev" }
      let(:lockfile_fixture_name) { "only_dev.lock" }

      its(:length) { is_expected.to eq(5) }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(1) }

        describe "the last dependency" do
          subject { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          it { is_expected.to_not be_production }
          its(:name) { is_expected.to eq("pytest") }
          its(:version) { is_expected.to eq("3.3.1") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with dependency names that need normalising" do
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(3) }

        describe "the first dependency" do
          subject { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with the version specified in a hash" do
      let(:pipfile_fixture_name) { "version_hash" }
      let(:lockfile_fixture_name) { "version_hash.lock" }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with a Pipfile that isn't parseable" do
      let(:pipfile_fixture_name) { "unparseable" }

      it "raises a Dependabot::DependencyFileNotParseable error" do
        expect { parser.dependency_set }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("Pipfile")
          end
      end
    end

    context "with a Pipfile.lock that isn't parseable" do
      let(:lockfile_fixture_name) { "unparseable.lock" }

      it "raises a Dependabot::DependencyFileNotParseable error" do
        expect { parser.dependency_set }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("Pipfile.lock")
          end
      end
    end

    context "with no entry in the Pipfile.lock" do
      let(:pipfile_fixture_name) { "not_in_lockfile" }
      let(:lockfile_fixture_name) { "only_dev.lock" }

      it "excludes the missing dependency" do
        expect(dependencies.map(&:name)).to_not include("missing")
      end

      describe "the dependency" do
        subject { dependencies.find { |d| d.name == "pytest" } }
        let(:expected_requirements) do
          [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("pytest") }
        its(:version) { is_expected.to eq("3.3.1") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a git source" do
      let(:pipfile_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source.lock" }

      it "excludes the git dependency" do
        expect(dependencies.map(&:name)).to_not include("django")
      end

      describe "the dependency" do
        subject { dependencies.find { |d| d.name == "requests" } }
        let(:expected_requirements) do
          [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.4") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end
  end
end
