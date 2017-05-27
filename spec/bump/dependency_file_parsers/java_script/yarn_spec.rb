# frozen_string_literal: true
require "spec_helper"
require "bump/dependency_file"
require "bump/dependency_file_parsers/java_script/yarn"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Bump::DependencyFileParsers::JavaScript::Yarn do
  it_behaves_like "a dependency file parser"

  let(:files) { [package_json, lockfile] }
  let(:package_json) do
    Bump::DependencyFile.new(name: "package.json", content: package_json_body)
  end
  let(:lockfile) do
    Bump::DependencyFile.new(name: "yarn.lock", content: lockfile_body)
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", "package.json")
  end
  let(:lockfile_body) do
    fixture("javascript", "lockfiles", "yarn.lock")
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("fetch-factory") }
        its(:version) { is_expected.to eq("0.0.1") }
      end
    end
  end
end
