# frozen_string_literal: true
require "spec_helper"
require "bump/dependency_file"
require "bump/dependency_file_parsers/node"

RSpec.describe Bump::DependencyFileParsers::Node do
  let(:files) { [package_json] }
  let(:package_json) do
    Bump::DependencyFile.new(name: "package.json", content: package_json_body)
  end
  let(:package_json_body) { fixture("node", "package_files", "package.json") }
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
