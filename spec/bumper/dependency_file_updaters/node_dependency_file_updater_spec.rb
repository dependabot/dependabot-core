require "spec_helper"
require "tmpdir"
require "./app/dependency_file"
require "./app/dependency"
require "./app/dependency_file_updaters/node_dependency_file_updater"

RSpec.describe DependencyFileUpdaters::NodeDependencyFileUpdater do
  before { WebMock.disable! }
  after { WebMock.enable! }
  let(:updater) do
    described_class.new(
      dependency_files: [package_json, npm_shrinkwrap_json],
      dependency: dependency
    )
  end
  let(:package_json) { DependencyFile.new(content: package_json_body, name: "package.json") }
  let(:package_json_body) { fixture("package.json") }
  let(:npm_shrinkwrap_json) do
    DependencyFile.new(content: fixture("npm-shrinkwrap.json"), name: "npm-shrinkwrap.json")
  end
  let(:dependency) { Dependency.new(name: "immutable", version: "1.7.0") }
  let(:tmp_path) { SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "new" do
    context "when the package.json is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(dependency_files: [npm_shrinkwrap_json], dependency: dependency)
      end

      it { is_expected.to raise_error(/No package.json!/) }
    end
  end

  # describe "#updated_dependency_files" do
    # subject(:updated_files) { updater.updated_dependency_files }
    # specify { expect { updated_files }.to_not change { Dir.entries(tmp_path) } }
    # specify { updated_files.each { |f| p f.name; expect(f).to be_a(DependencyFile) } }
    # its(:length) { is_expected.to eq(2) }
  # end

  describe "#updated_package_json_file" do
    subject(:updated_package_json_file) { updater.updated_package_json_file }

    its(:content) { is_expected.to include "\"immutable\": \"1.7.0\"" }
    its(:content) { is_expected.to include "\"etag\"" }
  end

  # describe "#updated_shrinkwrap" do
  #   subject(:file) { updater.updated_shrinkwrap }

  #   its(:content) { is_expected.to include "\"immutable\": \"1.7.0\"" }
  #   its(:content) { is_expected.to include "\"etag\"" }
  # end
end
