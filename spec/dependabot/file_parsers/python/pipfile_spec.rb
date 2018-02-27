# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/python/pipfile"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Python::Pipfile do
  it_behaves_like "a dependency file parser"

  let(:files) { [pipfile, lockfile] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(name: "Pipfile", content: pipfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Pipfile.lock", content: lockfile_body)
  end

  let(:pipfile_body) { fixture("python", "pipfiles", pipfile_fixture_name) }
  let(:lockfile_body) { fixture("python", "lockfiles", lockfile_fixture_name) }
  let(:pipfile_fixture_name) { "version_not_specified" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }
  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    describe "the first dependency" do
      subject { dependencies.first }
      let(:expected_requirements) do
        [
          {
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }
        ]
      end

      it { is_expected.to be_a(Dependabot::Dependency) }
      its(:name) { is_expected.to eq("requests") }
      its(:version) { is_expected.to eq("2.18.0") }
      its(:requirements) { is_expected.to eq(expected_requirements) }
    end

    context "with a version specified" do
      let(:pipfile_fixture_name) { "exact_version" }
      let(:lockfile_fixture_name) { "exact_version.lock" }

      its(:length) { is_expected.to eq(2) }

      describe "the dependency" do
        subject { dependencies.last }
        let(:expected_requirements) do
          [
            {
              requirement: "==3.4.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("pytest") }
        its(:version) { is_expected.to eq("3.4.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with only dev dependencies" do
      let(:pipfile_fixture_name) { "only_dev" }
      let(:lockfile_fixture_name) { "only_dev.lock" }

      its(:length) { is_expected.to eq(1) }

      describe "the last dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("pytest") }
        its(:version) { is_expected.to eq("3.3.1") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with dependency names that need normalising" do
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }

      its(:length) { is_expected.to eq(3) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with the version specified in a hash" do
      let(:pipfile_fixture_name) { "version_hash" }
      let(:lockfile_fixture_name) { "version_hash.lock" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with no entry in the Pipfile.lock" do
      let(:pipfile_fixture_name) { "not_in_lockfile" }
      let(:lockfile_fixture_name) { "only_dev.lock" }

      it "excludes the missing dependency" do
        expect(dependencies.map(&:name)).to eq(["pytest"])
      end

      describe "the dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ]
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
        expect(dependencies.map(&:name)).to eq(["requests"])
      end

      describe "the dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [
            {
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.4") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end
  end
end
