# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java_script/yarn"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::JavaScript::Yarn do
  it_behaves_like "a dependency file parser"

  let(:files) { [package_json, lockfile] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: package_json_body
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "yarn.lock", content: lockfile_body)
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", "package.json")
  end
  let(:lockfile_body) { fixture("javascript", "lockfiles", "yarn.lock") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("fetch-factory") }
        its(:version) { is_expected.to eq("0.0.1") }
        its(:requirements) do
          is_expected.to eq(
            [
              {
                requirement: "^0.0.1",
                file: "package.json",
                groups: ["dependencies"]
              }
            ]
          )
        end
      end
    end

    context "with only dev dependencies" do
      let(:package_json_body) do
        fixture("javascript", "package_files", "only_dev_dependencies.json")
      end
      let(:lockfile_body) do
        fixture("javascript", "lockfiles", "only_dev_dependencies.lock")
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("etag") }
        its(:version) { is_expected.to eq("1.8.0") }
        its(:requirements) do
          is_expected.to eq(
            [
              {
                requirement: "^1.0.0",
                file: "package.json",
                groups: ["devDependencies"]
              }
            ]
          )
        end
      end
    end
  end
end
