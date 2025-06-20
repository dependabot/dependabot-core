# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Vcpkg::FileFetcher do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/vcpkg-example",
      directory: directory
    )
  end
  let(:directory) { "/" }

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "returns true when vcpkg.json is present" do
      expect(described_class.required_files_in?(["vcpkg.json"])).to be(true)
    end

    it "returns true when vcpkg.json is present with other files" do
      expect(described_class.required_files_in?(["README.md", "vcpkg.json", "CMakeLists.txt"])).to be(true)
    end

    it "returns false when vcpkg.json is not present" do
      expect(described_class.required_files_in?(["README.md", "CMakeLists.txt"])).to be(false)
    end

    it "returns false for empty file list" do
      expect(described_class.required_files_in?([])).to be(false)
    end
  end

  describe ".required_files_message" do
    it "returns the correct message" do
      expect(described_class.required_files_message).to eq("Repo must contain a vcpkg.json file.")
    end
  end

  describe "#fetch_files" do
    context "with a simple manifest" do
      let(:project_name) { "simple_manifest" }

      it "fetches the vcpkg.json file" do
        files = file_fetcher_instance.files
        expect(files.map(&:name)).to contain_exactly("vcpkg.json")
      end
    end

    context "when no vcpkg.json file exists" do
      let(:project_name) { "no_manifest" }

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
          .with_message("No files found in /")
      end
    end

    context "when directory doesn't exist" do
      let(:project_name) { "simple_manifest" }
      let(:directory) { "/nonexistent" }

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
          .with_message("No files found in /nonexistent")
      end
    end
  end
end
