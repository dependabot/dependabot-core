require "spec_helper"
require "./app/dependency_file"
require "./app/dependency_file_parsers/node"

RSpec.describe DependencyFileParsers::Node do
  let(:files) { [package_json] }
  let(:package_json) { DependencyFile.new(name: "package.json", content: package_json_body) }
  let(:package_json_body) { fixture("package.json") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependency) }
        its(:name) { is_expected.to eq("immutable") }
        its(:version) { is_expected.to eq("1.0.1") }
      end
    end
  end
end
