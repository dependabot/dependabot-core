# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/python/pipfile"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Python::Pipfile do
  it_behaves_like "a dependency file parser"

  let(:files) { [pipfile, lockfile] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: pipfile_body
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Pipfile.lock", content: lockfile_body)
  end

  let(:pipfile_body) { fixture("python", "pipfiles", "version_not_specified") }
  let(:lockfile_body) do
    fixture("python", "lockfiles", "version_not_specified.lock")
  end
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
  end
end
