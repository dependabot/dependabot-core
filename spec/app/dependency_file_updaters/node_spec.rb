require "spec_helper"
require "./app/dependency"
require "./app/dependency_file"
require "./app/dependency_file_updaters/node"

RSpec.describe DependencyFileUpdaters::Node do
  before { WebMock.disable! }
  after { WebMock.enable! }
  let(:updater) do
    described_class.new(
      dependency_files: [package_json, yarn_lock],
      dependency: dependency
    )
  end
  let(:package_json) do
    DependencyFile.new(content: package_json_body, name: "package.json")
  end
  let(:package_json_body) { fixture("package_files", "package.json") }
  let(:yarn_lock) do
    DependencyFile.new(
      name: "yarn.lock",
      content: fixture("package_files", "yarn.lock")
    )
  end
  let(:dependency) { Dependency.new(name: "fetch-factory", version: "0.0.2") }
  let(:tmp_path) { SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "new" do
    context "when the package.json is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(dependency_files: [], dependency: dependency)
      end

      it { is_expected.to raise_error(/No package.json!/) }
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }
    specify { expect { updated_files }.to_not change { Dir.entries(tmp_path) } }
    specify { updated_files.each { |f| expect(f).to be_a(DependencyFile) } }
    its(:length) { is_expected.to eq(2) }
  end

  describe "#updated_package_json_file" do
    subject(:updated_package_json_file) { updater.updated_package_json_file }

    its(:content) { is_expected.to include "\"fetch-factory\": \"^0.0.2\"" }
    its(:content) { is_expected.to include "\"etag\": \"^1.0.0\"" }

    context "when the minor version is specified" do
      let(:dependency) do
        Dependency.new(name: "fetch-factory", version: "0.2.1")
      end
      let(:package_json_body) do
        fixture("package_files", "minor_version_specified.json")
      end

      its(:content) { is_expected.to include "\"fetch-factory\": \"0.2.x\"" }
    end
  end

  describe "#updated_yarn_lock" do
    subject(:file) { updater.updated_yarn_lock }
    it "has details of the updated item" do
      expect(file.content).
        to include("fetch-factory@^0.0.2")
    end
  end
end
