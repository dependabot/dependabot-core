# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/dependency_file_updaters/java_script"

RSpec.describe Bump::DependencyFileUpdaters::JavaScript do
  before { WebMock.allow_net_connect! }
  after { WebMock.disable_net_connect! }
  let(:updater) do
    described_class.new(
      dependency_files: [package_json, yarn_lock],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:package_json) do
    Bump::DependencyFile.new(content: package_json_body, name: "package.json")
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", "package.json")
  end
  let(:yarn_lock) do
    Bump::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("javascript", "package_files", "yarn.lock")
    )
  end
  let(:dependency) do
    Bump::Dependency.new(name: "fetch-factory", version: "0.0.2")
  end
  let(:tmp_path) { Bump::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "new" do
    context "when the package.json is missing" do
      subject { -> { updater } }
      let(:updater) do
        described_class.new(
          dependency_files: [],
          dependency: dependency,
          github_access_token: "token"
        )
      end

      it { is_expected.to raise_error(/No package.json!/) }
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Bump::DependencyFile) }
    end

    specify { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(2) }

    describe "the updated package_json_file" do
      subject(:updated_package_json_file) do
        updated_files.find { |f| f.name == "package.json" }
      end

      its(:content) { is_expected.to include "\"fetch-factory\": \"^0.0.2\"" }
      its(:content) { is_expected.to include "\"etag\": \"^1.0.0\"" }

      context "when the minor version is specified" do
        let(:dependency) do
          Bump::Dependency.new(name: "fetch-factory", version: "0.2.1")
        end
        let(:package_json_body) do
          fixture("javascript", "package_files", "minor_version_specified.json")
        end

        its(:content) { is_expected.to include "\"fetch-factory\": \"0.2.x\"" }
      end
    end

    describe "the updated yarn_lock" do
      subject(:updated_yarn_lock_file) do
        updated_files.find { |f| f.name == "yarn.lock" }
      end

      it "has details of the updated item" do
        expect(updated_yarn_lock_file.content).
          to include("fetch-factory@^0.0.2")
      end
    end
  end
end
